// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_distribution.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../notifications/controller/notification_settings_providers.dart';
import '../../../notifications/controller/notifications_controller.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';

class NotificationsSettingsScreen extends HookConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.watch(notificationsControllerProvider);

    final newChapters = ref
        .watch(notificationsNewChaptersEnabledProvider)
        .ifNull();
    final downloads = ref
        .watch(notificationsDownloadsEnabledProvider)
        .ifNull(true);
    final interval = ref.watch(notificationsCheckIntervalHoursProvider) ?? 6;
    final wifiOnly = ref.watch(notificationsWifiOnlyProvider).ifNull(true);
    final chargingOnly = ref.watch(notificationsChargingOnlyProvider).ifNull();
    final hideContent = ref.watch(notificationsHideContentProvider).ifNull();

    Future<void> reconcile() => controller.sync();

    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(l10n.notifications);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                SettingsGroupHeading(
                  label: l10n.notificationsSectionNewChapters,
                  first: true,
                ),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'notificationsNewChapters',
                      child: SwitchListTile(
                        title: Text(l10n.notificationsNewChapters),
                        subtitle: Text(l10n.notificationsNewChaptersSubtitle),
                        value: newChapters,
                        onChanged: (v) async {
                          ref
                              .read(
                                notificationsNewChaptersEnabledProvider
                                    .notifier,
                              )
                              .update(v);
                          if (v) await controller.requestPermissionAndSync();
                          await reconcile();
                        },
                      ),
                    ),
                    if (newChapters) ...[
                      SettingsHighlightTarget(
                        id: 'notificationsCheckInterval',
                        child: ListTile(
                          enabled: newChapters,
                          title: Text(l10n.notificationsCheckInterval),
                          trailing: DropdownButton<int>(
                            value: interval,
                            onChanged: (v) async {
                              if (v == null) return;
                              ref
                                  .read(
                                    notificationsCheckIntervalHoursProvider
                                        .notifier,
                                  )
                                  .update(v);
                              await reconcile();
                            },
                            items: const [1, 2, 3, 6, 12, 24]
                                .map(
                                  (h) => DropdownMenuItem(
                                    value: h,
                                    child: Text('${h}h'),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'notificationsWifiOnly',
                        child: SwitchListTile(
                          title: Text(l10n.notificationsWifiOnly),
                          value: wifiOnly,
                          onChanged: (v) async {
                            ref
                                .read(notificationsWifiOnlyProvider.notifier)
                                .update(v);
                            await reconcile();
                          },
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'notificationsChargingOnly',
                        child: SwitchListTile(
                          title: Text(l10n.notificationsChargingOnly),
                          value: chargingOnly,
                          onChanged: (v) async {
                            ref
                                .read(
                                  notificationsChargingOnlyProvider.notifier,
                                )
                                .update(v);
                            await reconcile();
                          },
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'notificationsCheckNow',
                        child: ListTile(
                          title: Text(l10n.notificationsCheckNow),
                          onTap: () => controller.checkNow(),
                        ),
                      ),
                    ],
                  ],
                ),
                SettingsGroupHeading(label: l10n.notificationsSectionOther),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'notificationsDownloadsComplete',
                      child: SwitchListTile(
                        title: Text(l10n.notificationsDownloadsComplete),
                        value: downloads,
                        onChanged: (v) async {
                          ref
                              .read(
                                notificationsDownloadsEnabledProvider.notifier,
                              )
                              .update(v);
                          await reconcile();
                        },
                      ),
                    ),
                    if (!isGooglePlayBuild)
                      SettingsHighlightTarget(
                        id: 'notificationsAppUpdates',
                        child: SwitchListTile(
                          title: Text(l10n.notificationsAppUpdates),
                          value: ref
                              .watch(notificationsAppUpdatesEnabledProvider)
                              .ifNull(),
                          onChanged: (v) async {
                            ref
                                .read(
                                  notificationsAppUpdatesEnabledProvider
                                      .notifier,
                                )
                                .update(v);
                            if (v) await controller.requestPermissionAndSync();
                            await reconcile();
                          },
                        ),
                      ),
                    SettingsHighlightTarget(
                      id: 'notificationsExtensionUpdates',
                      child: SwitchListTile(
                        title: Text(l10n.notificationsExtensionUpdates),
                        value: ref
                            .watch(notificationsExtensionUpdatesEnabledProvider)
                            .ifNull(),
                        onChanged: (v) async {
                          ref
                              .read(
                                notificationsExtensionUpdatesEnabledProvider
                                    .notifier,
                              )
                              .update(v);
                          if (v) await controller.requestPermissionAndSync();
                          await reconcile();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'notificationsHideContent',
                      child: SwitchListTile(
                        title: Text(l10n.notificationsHideContent),
                        subtitle: Text(l10n.notificationsHideContentSubtitle),
                        value: hideContent,
                        onChanged: (v) async {
                          ref
                              .read(notificationsHideContentProvider.notifier)
                              .update(v);
                          await reconcile();
                        },
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.notificationsReliabilityNote,
                    style: context.theme.textTheme.bodySmall?.copyWith(
                      color: context.theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
