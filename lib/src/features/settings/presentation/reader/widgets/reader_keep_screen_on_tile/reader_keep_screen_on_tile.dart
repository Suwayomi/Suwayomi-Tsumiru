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

part 'reader_keep_screen_on_tile.g.dart';

/// Persisted reader preference: keep the device screen awake while reading.
/// Default ON — reading is low-interaction, so we'd rather hold the screen than
/// let it sleep mid-page.
@riverpod
class KeepScreenOn extends _$KeepScreenOn
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.keepScreenOn);
}

class ReaderKeepScreenOnTile extends HookConsumerWidget {
  const ReaderKeepScreenOnTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.brightness_high_rounded),
      title: Text(context.l10n.readerKeepScreenOn),
      subtitle: Text(context.l10n.readerKeepScreenOnSubtitle),
      onChanged: ref.read(keepScreenOnProvider.notifier).update,
      value: ref.watch(keepScreenOnProvider).ifNull(true),
    );
  }
}
