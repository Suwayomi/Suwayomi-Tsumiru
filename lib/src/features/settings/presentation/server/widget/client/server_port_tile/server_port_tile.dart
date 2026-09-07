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
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../offline/data/background/background_download_controller_shim.dart';
import '../server_url_tile/server_url_tile.dart'
    show clearCredentialsForServerChange;

part 'server_port_tile.g.dart';

@riverpod
class ServerPort extends _$ServerPort with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.serverPort);

  @override
  Future<void> update(int? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          await clearCredentialsForServerChange(ref);
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }
}

@riverpod
class ServerPortToggle extends _$ServerPortToggle
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
    DBKeys.serverPortToggle,
    initial: kIsWeb ? false : DBKeys.serverPortToggle.initial,
  );

  @override
  Future<void> update(bool? value) async {
    if (value == state) return;
    final lease = ref.keepAlive();
    try {
      await ref.read(backgroundDownloadControllerProvider).changeIdentity(
        () async {
          await clearCredentialsForServerChange(ref);
          super.update(value);
        },
      );
    } finally {
      lease.close();
    }
  }
}

class ServerPortTile extends ConsumerWidget {
  const ServerPortTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverPort = ref.watch(serverPortProvider);
    final serverToggle = ref.watch(serverPortToggleProvider).ifNull();
    return SettingsPropTile(
      title: context.l10n.serverPort,
      subtitle: serverToggle ? serverPort.toString() : null,
      leading: const Icon(Icons.dns_rounded),
      trailing: Switch(
        value: serverToggle,
        onChanged: (value) async {
          await ref.read(serverPortToggleProvider.notifier).update(value);
        },
      ),
      type: SettingsPropType<void>.numberPicker(
        min: 0,
        max: 65535,
        value: serverPort,
        onChanged: serverToggle
            ? (port) async {
                await ref.read(serverPortProvider.notifier).update(port);
                return;
              }
            : null,
      ),
    );
  }
}
