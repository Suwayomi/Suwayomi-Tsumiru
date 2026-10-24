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
import '../../../../../../../utils/crash/diagnostics.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../offline/data/background/background_download_controller_shim.dart';
import '../../../../connection/prompt_sign_in.dart';
import '../../credential_popup/credentials_popup.dart';
import 'hosted_base_uri.dart';
import 'server_search_button.dart';
import 'web_default_server_url.dart';

part 'server_url_tile.g.dart';

@riverpod
class ServerUrl extends _$ServerUrl with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(
    DBKeys.serverUrl,
    initial: kIsWeb ? webInitialServerUrl() : DBKeys.serverUrl.initial,
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

  Future<void> setActive(String? value, {bool Function()? isCurrent}) async {
    if (value == state || isCurrent?.call() == false) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          if (isCurrent?.call() == false) return;
          super.update(value);
        },
        preserveSession: true,
      );
    } finally {
      lease.close();
    }
  }
}

/// Migrates the legacy single URL on first read.
@riverpod
class ServerExternalUrl extends _$ServerExternalUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return initialize(
      DBKeys.serverExternalUrl,
      initial:
          prefs.getString(DBKeys.serverUrl.name) ??
          (kIsWeb ? webInitialServerUrl() : DBKeys.serverUrl.initial),
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

/// LAN address for the same server; changing it preserves the shared credentials.
@riverpod
class ServerLanUrl extends _$ServerLanUrl
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.serverLanUrl);

  @override
  void update(String? value) {
    super.update(_normaliseUrl(value));
  }
}

String webInitialServerUrl() {
  final candidate = webDefaultServerUrl(readHostedBaseUri());
  final parsed = Uri.tryParse(candidate);
  if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
    return candidate;
  }
  return Uri.base.origin;
}

String? _normaliseUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

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
    // An auth-required response proves reachability even when the shared session expired.
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

/// Handles asynchronous connectivity failures, including missing D-Bus in sandboxed Linux.
@visibleForTesting
StreamSubscription<List<ConnectivityResult>> listenToConnectivity(
  Stream<List<ConnectivityResult>> changes,
  void Function() onChange,
) => changes.listen((_) => onChange(), onError: (_) {}, cancelOnError: false);

@Riverpod(keepAlive: true)
class ServerEndpointResolver extends _$ServerEndpointResolver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _refreshing = false;

  @override
  String? build() {
    final external =
        ref.watch(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial;
    ref.watch(serverLanUrlProvider);
    ref.watch(
      authCredentialsStoreProvider.select(
        (value) => (
          value.value?.sessionEpoch ?? 0,
          value.value?.sessionChanging ?? false,
        ),
      ),
    );
    // Connectivity plugins or D-Bus may be unavailable; startup selection must still work.
    try {
      _connectivitySubscription ??= listenToConnectivity(
        Connectivity().onConnectivityChanged,
        () => unawaited(refresh(trigger: 'connectivity')),
      );
    } catch (_) {}
    ref.onDispose(() => _connectivitySubscription?.cancel());
    Future.microtask(() => refresh(trigger: 'startup'));
    return external;
  }

  Future<void> refresh({String trigger = 'connection-failure'}) async {
    if (_refreshing) return;
    final credentials = ref.read(authCredentialsStoreProvider.notifier);
    if (credentials.sessionChanging) return;
    final epoch = credentials.sessionEpoch;
    final external =
        ref.read(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial;
    final lan = ref.read(serverLanUrlProvider);
    bool current() =>
        ref.mounted &&
        !credentials.sessionChanging &&
        credentials.sessionEpoch == epoch &&
        (ref.read(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial) ==
            external &&
        ref.read(serverLanUrlProvider) == lan;
    _refreshing = true;
    try {
      final probe = Stopwatch();
      bool? lanReachable;
      final selected = await selectServerUrl(
        externalUrl: external,
        lanUrl: lan,
        isReachable: (url) async {
          probe.start();
          lanReachable = await serverUrlIsReachable(url);
          probe.stop();
          return lanReachable!;
        },
      );
      if (!current()) return;
      final previous = ref.read(serverUrlProvider);
      if (lanReachable != null || selected != previous) {
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] endpoint: trigger=$trigger '
          'lan=${switch (lanReachable) {
            null => 'none',
            true => 'reachable',
            false => 'unreachable',
          }} probeMs=${probe.elapsedMilliseconds} '
          'selected=${selected == external ? 'external' : 'lan'}'
          '${selected == previous ? '' : ' switched'}\n',
        );
      }
      await ref
          .read(serverUrlProvider.notifier)
          .setActive(selected, isCurrent: current);
      if (current()) state = selected;
    } finally {
      _refreshing = false;
      if (ref.mounted && !credentials.sessionChanging && !current()) {
        unawaited(refresh());
      }
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

/// Clears credentials and bumps the epoch so an endpoint change cannot leak them to another server.
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
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          stayOnConnectionAfterIdentityChange();
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
