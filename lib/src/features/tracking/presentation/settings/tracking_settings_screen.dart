// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/compact_switch.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../settings/search/settings_search_registry.dart';
import '../../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../../data/tracker_repository.dart';
import '../../domain/tracking_settings_providers.dart';
import 'widgets/settings_tracker_tile.dart';

class TrackingSettingsScreen extends ConsumerWidget {
  const TrackingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateAfterReading = ref
        .watch(updateProgressAfterReadingProvider)
        .ifNull(true);
    final updateManualMarkRead = ref
        .watch(updateProgressManualMarkReadProvider)
        .ifNull(true);
    final trackersAsync = ref.watch(trackersProvider);
    Future<void> update(Future<void> Function() write) async {
      await AppUtils.guard(write, ref.read(toastProvider));
    }

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.tracking);
    final content = ListTileTheme(
      data: ListTileThemeData(
        subtitleTextStyle: TextStyle(
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Scaffold(
        appBar: topBar
            ? null
            : AppBar(
                leading: detailNavigationBackButton(context),
                title: title,
              ),
        body: SettingsHighlightScope(
          child: Center(
            child: ConstrainedBox(
              constraints: settingsPageConstraints(context),
              child: ListView(
                padding: settingsPagePadding(context),
                children: [
                  const SizedBox(height: 16),
                  SettingsGroupCard(
                    children: [
                      SettingsHighlightTarget(
                        id: 'updateProgressAfterReading',
                        child: CompactSwitchListTile(
                          title: Text(context.l10n.updateProgressAfterReading),
                          value: updateAfterReading,
                          onChanged: (value) => update(
                            () => ref
                              .read(updateProgressAfterReadingProvider.notifier)
                              .update(value),
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'updateProgressManualMarkRead',
                        child: CompactSwitchListTile(
                          title: Text(
                            context.l10n.updateProgressManualMarkRead,
                          ),
                          subtitle: Text(
                            context.l10n.updateProgressManualMarkReadDesc,
                          ),
                          value: updateManualMarkRead,
                          onChanged: (value) => update(
                            () => ref
                              .read(
                                updateProgressManualMarkReadProvider.notifier,
                              )
                              .update(value),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroupHeading(label: context.l10n.trackers),
                  trackersAsync.showUiWhenData(
                    context,
                    (trackers) => trackers.isEmpty
                        ? const SizedBox.shrink()
                        : SettingsGroupCard(
                            children: trackers
                                .map((t) => SettingsTrackerTile(tracker: t))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: content,
    );
  }
}
