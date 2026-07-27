// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../widgets/slider_setting_tile/slider_setting_tile.dart';

part 'reader_mouse_scroll_speed_slider.g.dart';

@riverpod
class ReaderMouseScrollSpeedKey extends _$ReaderMouseScrollSpeedKey
    with SharedPreferenceClientMixin<double> {
  @override
  double? build() => initialize(DBKeys.readerMouseScrollSpeed);
}

class ReaderMouseScrollSpeedSlider extends ConsumerWidget {
  const ReaderMouseScrollSpeedSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(readerMouseScrollSpeedKeyProvider) ??
        DBKeys.readerMouseScrollSpeed.initial;
    return SliderSettingTile(
      icon: Icons.mouse_rounded,
      title: context.l10n.readerMouseScrollSpeed,
      value: speed,
      getSliderLabel: (val) => '${val.toStringAsFixed(1)}x',
      onChanged: ref.read(readerMouseScrollSpeedKeyProvider.notifier).update,
      defaultValue: DBKeys.readerMouseScrollSpeed.initial,
      min: 0.5,
      max: 4,
    );
  }
}
