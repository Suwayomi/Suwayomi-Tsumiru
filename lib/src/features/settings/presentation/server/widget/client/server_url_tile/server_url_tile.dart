// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../../constants/db_keys.dart';
import '../../../../../../../constants/endpoints.dart';
import '../../../../../../../features/auth/data/auth_credentials_store.dart';
import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../offline/data/background/background_download_controller_shim.dart';
import '../../credential_popup/credentials_popup.dart';
import 'server_search_button.dart';

part 'server_url_tile.g.dart';

@riverpod
class ServerUrl extends _$ServerUrl with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(
    DBKeys.serverUrl,
    initial: kIsWeb ? Uri.base.origin : DBKeys.serverUrl.initial,
  );

  @override
  Future<void> update(String? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          if (_isDifferentHost(state, value)) {
            await clearCredentialsForServerChange(ref);
          }
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }

  Future<void> setActive(String? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }
}

/// User-configured remote URL. Existing installations migrate their old single
/// URL into this preference on first read.
@riverpod
class ServerExternalUrl extends _$ServerExternalUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return initialize(
      DBKeys.serverExternalUrl,
      initial:
          prefs.getString(DBKeys.serverUrl.name) ?? DBKeys.serverUrl.initial,
    );
  }

  @override
  Future<void> update(String? value) async {
    final normalised = _normaliseUrl(value);
    if (normalised == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          if (_isDifferentHost(state, normalised)) {
            await clearCredentialsForServerChange(ref);
          }
          super.update(normalised);
          await ref.read(serverUrlProvider.notifier).setActive(normalised);
        },
      );
    } finally {
      lease.close();
    }
  }
}

/// Optional LAN URL for the same Suwayomi instance. Changing it never clears
/// credentials: its entire purpose is to share the remote endpoint's login.
@riverpod
class ServerLanUrl extends _$ServerLanUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.serverLanUrl);

  @override
  void update(String? value) {
    super.update(_normaliseUrl(value));
    // The active resolver observes this preference and re-checks immediately.
  }
}

String? _normaliseUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// Chooses an endpoint. Kept pure apart from the injected probe so it can be
/// tested without a device network or a real Suwayomi server.
Future<String> selectServerUrl({
  required String externalUrl,
  required String? lanUrl,
  required Future<bool> Function(String url) isReachable,
}) async {
  final lan = _normaliseUrl(lanUrl);
  if (lan == null) return externalUrl;
  return await isReachable(lan) ? lan : externalUrl;
}

Future<bool> serverUrlIsReachable(String url, {http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    // An auth-required response proves that this host is reachable too. Do not
    // follow this with a GraphQL request: the shared session may be expired.
    await httpClient
        .head(Uri.parse(Endpoints.baseApi(baseUrl: url, appendApiToUrl: false)))
        .timeout(const Duration(seconds: 2));
    return true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}

/// Keeps [serverUrlProvider] pointed at the preferred endpoint. It runs at
/// startup and each interface change, so moving between Wi-Fi and mobile data
/// automatically re-evaluates the LAN address.
@Riverpod(keepAlive: true)
class ServerEndpointResolver extends _$ServerEndpointResolver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _refreshing = false;

  @override
  String? build() {
    final external =
        ref.watch(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial;
    ref.watch(serverLanUrlProvider);
    // Desktop and widget-test platforms may not register connectivity_plus.
    // Startup selection still works there; they simply cannot receive later
    // interface-change callbacks.
    try {
      _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen(
        (_) => unawaited(refresh()),
      );
    } catch (_) {}
    ref.onDispose(() => _connectivitySubscription?.cancel());
    Future.microtask(refresh);
    return external;
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final external =
          ref.read(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial;
      final selected = await selectServerUrl(
        externalUrl: external,
        lanUrl: ref.read(serverLanUrlProvider),
        isReachable: serverUrlIsReachable,
      );
      await ref.read(serverUrlProvider.notifier).setActive(selected);
      state = selected;
    } finally {
      _refreshing = false;
    }
  }
}

bool _isDifferentHost(String? a, String? b) {
  if (a == null || b == null || a == b) return false;
  final ua = Uri.tryParse(a);
  final ub = Uri.tryParse(b);
  if (ua == null || ub == null) return true;
  return ua.scheme != ub.scheme || ua.host != ub.host || ua.port != ub.port;
}

/// Wipe credentials and bump the epoch on an endpoint change (URL, port, or
/// port toggle) so the old server's creds can't reach the new one.
Future<void> clearCredentialsForServerChange(Ref ref) async {
  await ref.read(credentialsProvider.notifier).set(null);
  await ref
      .read(authCredentialsStoreProvider.notifier)
      .clearAllForServerSwitch();
}

class ServerUrlTile extends ConsumerWidget {
  const ServerUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverExternalUrlProvider);
    return SettingsPropTile(
      title: context.l10n.serverUrl,
      subtitle: serverUrl,
      leading: const Icon(Icons.computer_rounded),
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          await ref.read(serverExternalUrlProvider.notifier).update(value);
          return;
        },
      ),
    );
  }
}

class ServerLanUrlTile extends ConsumerWidget {
  const ServerLanUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverLanUrlProvider);
    return SettingsPropTile(
      title: context.l10n.serverLanUrl,
      subtitle: serverUrl ?? context.l10n.serverLanUrlOptional,
      leading: const Icon(Icons.home_rounded),
      trailing: !kIsWeb ? const ServerSearchButton() : null,
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverLanUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          ref.read(serverLanUrlProvider.notifier).update(value);
        },
      ),
    );
  }
}
