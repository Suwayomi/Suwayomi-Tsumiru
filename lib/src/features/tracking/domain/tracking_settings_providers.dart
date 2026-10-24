// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../utils/webui_meta/webui_settings.dart';

part 'tracking_settings_providers.g.dart';

@riverpod
class UpdateProgressAfterReading extends _$UpdateProgressAfterReading {
  @override
  bool? build() {
    final metas = ref.watch(webUiSettingsProvider).value ?? {};
    final value = readWebUiValue(metas, 'updateProgressAfterReading');
    return value == null
        ? ref
                  .watch(sharedPreferencesProvider)
                  .getBool(DBKeys.updateProgressAfterReading.name) ??
              true
        : decodeWebUiBool(value);
  }

  Future<void> update(bool? value) async {
    if (value == null) return;
    await ref
        .read(webUiSettingsProvider.notifier)
        .write('updateProgressAfterReading', encodeWebUiBool(value));
  }
}

@riverpod
class UpdateProgressManualMarkRead extends _$UpdateProgressManualMarkRead {
  @override
  bool? build() {
    final metas = ref.watch(webUiSettingsProvider).value ?? {};
    final value = readWebUiValue(metas, 'updateProgressManualMarkRead');
    return value == null
        ? ref
                  .watch(sharedPreferencesProvider)
                  .getBool(DBKeys.updateProgressManualMarkRead.name) ??
              true
        : decodeWebUiBool(value);
}

  Future<void> update(bool? value) async {
    if (value == null) return;
    await ref
        .read(webUiSettingsProvider.notifier)
        .write('updateProgressManualMarkRead', encodeWebUiBool(value));
  }
}
