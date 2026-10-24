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
import '../../../../../../widgets/compact_switch.dart';

part 'tap_zones_overlay.g.dart';

/// Flashes the tap zones each time a chapter opens.
@riverpod
class ShowTapZonesOverlay extends _$ShowTapZonesOverlay
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showTapZonesOverlay);
}

/// Shows zones once for first-time users, independently of the recurring overlay setting.
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
    return CompactSwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(context.l10n.showTapZonesOverlay),
      subtitle: Text(context.l10n.showTapZonesOverlaySubtitle),
      value: ref.watch(showTapZonesOverlayProvider).ifNull(),
      onChanged: ref.read(showTapZonesOverlayProvider.notifier).update,
    );
  }
}
