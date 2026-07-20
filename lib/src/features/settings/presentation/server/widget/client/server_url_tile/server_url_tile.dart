// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../../constants/db_keys.dart';
import '../../../../../../../features/auth/data/auth_credentials_store.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
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
  void update(String? value) {
    final previous = state;
    // Clear before publishing so the rebuild it triggers can't send A's creds to B.
    if (_isDifferentHost(previous, value)) clearCredentialsForServerChange(ref);
    super.update(value);
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
void clearCredentialsForServerChange(Ref ref) {
  ref.read(credentialsProvider.notifier).set(null);
  ref.read(authCredentialsStoreProvider.notifier).clearAllForServerSwitch();
}

class ServerUrlTile extends ConsumerWidget {
  const ServerUrlTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    return SettingsPropTile(
      title: context.l10n.serverUrl,
      subtitle: serverUrl,
      leading: const Icon(Icons.computer_rounded),
      trailing: !kIsWeb ? const ServerSearchButton() : null,
      type: SettingsPropType<void>.textField(
        hintText: context.l10n.serverUrlHintText,
        value: serverUrl,
        onChanged: (value) async {
          final tempUrl = value.endsWith('/')
              ? value.substring(0, value.length - 1)
              : value;
          ref.read(serverUrlProvider.notifier).update(tempUrl);
          return;
        },
      ),
    );
  }
}
