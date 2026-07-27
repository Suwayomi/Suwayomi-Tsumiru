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

part 'tap_zones_overlay.g.dart';

/// Flash the tap zones every time a chapter opens. Off by default, like
/// Komikku.
@riverpod
class ShowTapZonesOverlay extends _$ShowTapZonesOverlay
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showTapZonesOverlay);
}

/// True until the zones have been shown once. Gives someone who has never seen
/// them a single look, then never again unless they ask for it.
@riverpod
class TapZonesOverlayUnseen extends _$TapZonesOverlayUnseen
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.tapZonesOverlayUnseen);
}

class ShowTapZonesOverlayTile extends ConsumerWidget {
  const ShowTapZonesOverlayTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.touch_app_rounded),
      title: Text(context.l10n.showTapZonesOverlay),
      subtitle: Text(context.l10n.showTapZonesOverlaySubtitle),
      value: ref.watch(showTapZonesOverlayProvider).ifNull(),
      onChanged: ref.read(showTapZonesOverlayProvider.notifier).update,
    );
  }
}
