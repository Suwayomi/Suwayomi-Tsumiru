// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/section_title.dart';
import '../../data/tracker_repository.dart';
import '../../domain/tracking_settings_providers.dart';
import 'widgets/settings_tracker_tile.dart';

class TrackingSettingsScreen extends ConsumerWidget {
  const TrackingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateAfterReading =
        ref.watch(updateProgressAfterReadingProvider).ifNull(true);
    final updateManualMarkRead =
        ref.watch(updateProgressManualMarkReadProvider).ifNull(true);
    final trackersAsync = ref.watch(trackersProvider);

    return ListTileTheme(
      data: const ListTileThemeData(
        subtitleTextStyle: TextStyle(color: Colors.grey),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.tracking),
        ),
        body: ListView(
          children: [
            SwitchListTile(
              title: Text(context.l10n.updateProgressAfterReading),
              value: updateAfterReading,
              onChanged: (value) => ref
                  .read(updateProgressAfterReadingProvider.notifier)
                  .update(value),
            ),
            SwitchListTile(
              title: Text(context.l10n.updateProgressManualMarkRead),
              subtitle: Text(context.l10n.updateProgressManualMarkReadDesc),
              value: updateManualMarkRead,
              onChanged: (value) => ref
                  .read(updateProgressManualMarkReadProvider.notifier)
                  .update(value),
            ),
            SectionTitle(title: context.l10n.trackers),
            trackersAsync.showUiWhenData(
              context,
              (trackers) => Column(
                children: trackers
                    .map((t) => SettingsTrackerTile(tracker: t))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
