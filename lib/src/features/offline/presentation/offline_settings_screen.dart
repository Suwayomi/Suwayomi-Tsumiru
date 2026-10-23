// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../../widgets/desktop/desktop_top_bar.dart';
import '../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../notifications/controller/notification_settings_providers.dart';
import '../../notifications/controller/notifications_controller.dart';
import '../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../../settings/search/settings_search_registry.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../data/background/catchup_settings.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import '../data/offline_settings_providers.dart';
import 'inactive_account_catalogue_tiles.dart';
import 'offline_server_mismatch_banner.dart';
import 'offline_settings_format.dart';

/// Labels for the "after reading automatically delete" select (0 = disabled,
/// N = the Nth chapter behind), matching the Suwayomi-WebUI wording.
String _deleteWhileReadingLabel(BuildContext context, int value) =>
    switch (value) {
      1 => context.l10n.deleteWhileReadingLastRead,
      2 => context.l10n.deleteWhileReadingSecondToLast,
      3 => context.l10n.deleteWhileReadingThirdToLast,
      4 => context.l10n.deleteWhileReadingFourthToLast,
      5 => context.l10n.deleteWhileReadingFifthToLast,
      _ => context.l10n.deleteWhileReadingDisabled,
    };

/// One "Delete chapters" card, shared by the server and on-device tabs of the
/// Downloads page — identical controls, different backing settings.
///
/// [whileReadingSubOptions] renders directly below the "delete finished
/// chapters while reading" row — the option that controls whether they're
/// meaningful at all — rather than at the end of the card, so a
/// dependent toggle stays visually attached to what governs it.
///
/// [targetIdPrefix] namespaces the three rows' highlight ids per tab
/// ('server' / 'device'): the two tabs share titles but never target ids, so
/// search can scroll to the right tab's row.
List<Widget> deleteChaptersSection(
  BuildContext context, {
  required String title,
  required String description,
  required DeleteChaptersSettings settings,
  required Future<void> Function(bool) onManual,
  required void Function(int) onWhileReading,
  required Future<void> Function(bool) onBookmark,
  required String targetIdPrefix,
  List<Widget> whileReadingSubOptions = const [],
  bool first = false,
}) => [
  SettingsGroupHeading(label: title, first: first),
  Padding(
    padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
    child: Text(
      description,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.theme.hintColor,
      ),
    ),
  ),
  SettingsGroupCard(
    children: [
      SettingsHighlightTarget(
        id: '${targetIdPrefix}DeleteManuallyMarkedRead',
        child: SettingsPropTile(
          title: context.l10n.deleteChapterAfterManuallyMarkedRead,
          type: SettingsPropType.switchTile(
            value: settings.deleteManuallyMarkedRead,
            onChanged: onManual,
          ),
        ),
      ),
      SettingsHighlightTarget(
        id: '${targetIdPrefix}DeleteWhileReading',
        child: ListTile(
          title: Text(context.l10n.deleteFinishedChaptersWhileReading),
          subtitle: Text(
            _deleteWhileReadingLabel(context, settings.deleteWhileReading),
          ),
          onTap: () => showDialog(
            context: context,
            builder: (context) => RadioListPopup<int>(
              title: context.l10n.deleteFinishedChaptersWhileReading,
              optionList: const [0, 1, 2, 3, 4, 5],
              getOptionTitle: (value) =>
                  _deleteWhileReadingLabel(context, value),
              value: settings.deleteWhileReading,
              onChange: (value) {
                onWhileReading(value);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            animationStyle: context.motionStyle,
          ),
        ),
      ),
      ...whileReadingSubOptions,
      SettingsHighlightTarget(
        id: '${targetIdPrefix}DeleteWithBookmark',
        child: SettingsPropTile(
          title: context.l10n.allowDeletingBookmarkedChapters,
          type: SettingsPropType.switchTile(
            value: settings.deleteWithBookmark,
            onChanged: onBookmark,
          ),
        ),
      ),
    ],
  ),
];

/// Indented dependent toggle, shown only while its controlling option makes
/// it meaningful — same treatment as the reader settings' sub-toggles, so a
/// dependent option doesn't read as a normal, independent one.
class SubSwitchTile extends StatelessWidget {
  const SubSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// The on-device (offline) download + storage settings, as a flat list of
/// tiles so it can be composed into the Downloads screen's "On-device" tab.
/// Returns a single "not available" note when the offline feature is disabled.
List<Widget> buildOnDeviceStorageTiles(BuildContext context, WidgetRef ref) {
  if (!ref.watch(offlineEnabledProvider)) {
    return [
      const InactiveAccountCatalogueTiles(),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.l10n.offlineNotAvailable),
      ),
    ];
  }
  final localDelete = ref.watch(localDeleteSettingsProvider);
  final backgroundCatchup = ref.watch(backgroundCatchupEnabledProvider);
  return [
    const InactiveAccountCatalogueTiles(),
    const OfflineServerMismatchBanner(showAfterDismissal: true),
    SettingsGroupHeading(
      label: context.l10n.offlineDownloadsSection,
      first: true,
    ),
    SettingsGroupCard(
      children: [
        SettingsHighlightTarget(
          id: 'offlineWifiOnly',
          child: SettingsPropTile(
            title: context.l10n.downloadOverWifiOnly,
            type: SettingsPropType.switchTile(
              value: ref.watch(offlineWifiOnlyProvider) ?? true,
              onChanged: (v) async {
                ref.read(offlineWifiOnlyProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'offlineConcurrency',
          child: SettingsPropTile(
            title: context.l10n.offlineConcurrencyLabel,
            subtitle: context.l10n.offlineConcurrencyValue(
              ref.watch(offlineDownloadConcurrencyProvider) ?? 2,
            ),
            type: SettingsPropType.numberSlider(
              min: 1,
              max: 8,
              value: ref.watch(offlineDownloadConcurrencyProvider) ?? 2,
              onChanged: (v) async {
                ref.read(offlineDownloadConcurrencyProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
      ],
    ),
    // On-device downloads (this phone). Independent, default off.
    ...deleteChaptersSection(
      context,
      title: context.l10n.deleteOnDeviceDownloads,
      description: context.l10n.deleteOnDeviceDownloadsDescription,
      settings: localDelete,
      onManual: (v) async =>
          ref.read(localDeleteManuallyMarkedReadProvider.notifier).update(v),
      onWhileReading: (v) =>
          ref.read(localDeleteWhileReadingProvider.notifier).update(v),
      onBookmark: (v) async =>
          ref.read(localDeleteWithBookmarkProvider.notifier).update(v),
      targetIdPrefix: 'device',
      // Only meaningful when the keep window has at least 1 protected
      // slot — rendered right under the option that controls it.
      whileReadingSubOptions: localDelete.deleteWhileReading >= 2
          ? [
              SettingsHighlightTarget(
                id: 'downloadProtectionWindow',
                child: SubSwitchTile(
                  title: context.l10n.downloadProtectionWindowTitle,
                  subtitle: context.l10n.downloadProtectionWindowDescription,
                  value:
                      ref.watch(localDownloadProtectionWindowProvider) ?? false,
                  onChanged: (v) async => ref
                      .read(localDownloadProtectionWindowProvider.notifier)
                      .update(v),
                ),
              ),
            ]
          : const [],
    ),
    // Background wake-ups are Android's WorkManager; on other platforms the
    // in-app triggers (launch, update-finish, queue-drain) are the coverage,
    // so the switch would be a lie there.
    if (isAndroidNative) ...[
      SettingsGroupHeading(label: context.l10n.offlineBackgroundSection),
      SettingsGroupCard(
        children: [
          SettingsHighlightTarget(
            id: 'backgroundCatchup',
            child: SettingsPropTile(
              title: context.l10n.downloadNewChaptersInBackground,
              subtitle: context.l10n.downloadNewChaptersInBackgroundDescription,
              type: SettingsPropType.switchTile(
                value: backgroundCatchup,
                onChanged: (v) async {
                  await ref
                      .read(backgroundCatchupEnabledProvider.notifier)
                      .setEnabled(v);
                  return null;
                },
              ),
            ),
          ),
          // Both sub-options are meaningless with the run itself switched
          // off — nested the same way the Notifications screen nests its
          // own check interval under "New chapters". The interval is the
          // SAME WorkManager schedule that check uses (one shared periodic
          // job), so it's shown here too rather than only being reachable
          // from a screen this toggle doesn't depend on.
          if (backgroundCatchup) ...[
            SettingsHighlightTarget(
              id: 'backgroundCheckInterval',
              child: ListTile(
                title: Text(context.l10n.notificationsCheckInterval),
                trailing: DropdownButton<int>(
                  value:
                      ref.watch(notificationsCheckIntervalHoursProvider) ?? 6,
                  onChanged: (v) async {
                    if (v == null) return;
                    ref
                        .read(notificationsCheckIntervalHoursProvider.notifier)
                        .update(v);
                    await ref.read(notificationsControllerProvider).sync();
                  },
                  items: const [1, 2, 3, 6, 12, 24]
                      .map(
                        (h) => DropdownMenuItem(value: h, child: Text('${h}h')),
                      )
                      .toList(),
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'backgroundFetchFiles',
              child: SettingsPropTile(
                title: context.l10n.backgroundCatchupFetchFiles,
                subtitle: context.l10n.backgroundCatchupFetchFilesDescription,
                type: SettingsPropType.switchTile(
                  value: ref.watch(backgroundCatchupDownloadEnabledProvider),
                  onChanged: (v) async {
                    await ref
                        .read(backgroundCatchupDownloadEnabledProvider.notifier)
                        .setEnabled(v);
                    return null;
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    ],
    SettingsGroupHeading(label: context.l10n.offlineStorageSection),
    SettingsGroupCard(
      children: [
        // Storage used is info only (no action), so it stays out of search.
        ListTile(
          title: Text(context.l10n.offlineStorageUsage),
          subtitle: Text(
            formatBytes(ref.watch(offlineUsageBytesProvider).value ?? 0),
          ),
        ),
        SettingsHighlightTarget(
          id: 'offlineStorageCapEnable',
          child: SettingsPropTile(
            title: context.l10n.offlineStorageCapEnable,
            type: SettingsPropType.switchTile(
              value: ref.watch(offlineStorageCapEnabledProvider) ?? false,
              onChanged: (v) async {
                ref.read(offlineStorageCapEnabledProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'offlineStorageCapLimit',
          child: SettingsPropTile(
            title: context.l10n.offlineStorageCapLimit,
            subtitle: context.l10n.offlineMegabytes(
              ref.watch(offlineStorageCapMbProvider) ?? 2000,
            ),
            type: SettingsPropType.numberSlider(
              min: 100,
              max: 50000,
              value: ref.watch(offlineStorageCapMbProvider) ?? 2000,
              onChanged: (v) async {
                ref.read(offlineStorageCapMbProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'offlineTimeEvictEnable',
          child: SettingsPropTile(
            title: context.l10n.offlineTimeEvictEnable,
            type: SettingsPropType.switchTile(
              value: ref.watch(offlineTimeEvictEnabledProvider) ?? false,
              onChanged: (v) async {
                ref.read(offlineTimeEvictEnabledProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'offlineKeepDays',
          child: SettingsPropTile(
            title: context.l10n.offlineKeepDaysLabel,
            subtitle: context.l10n.offlineDays(
              ref.watch(offlineKeepDaysProvider) ?? 30,
            ),
            type: SettingsPropType.numberSlider(
              min: 1,
              max: 365,
              value: ref.watch(offlineKeepDaysProvider) ?? 30,
              onChanged: (v) async {
                ref.read(offlineKeepDaysProvider.notifier).update(v);
                return null;
              },
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    SettingsGroupCard(
      children: [
        SettingsHighlightTarget(
          id: 'removeAllDownloads',
          child: ListTile(
            title: Text(context.l10n.offlineRemoveAllDownloads),
            onTap: () async {
              final current = ref
                  .read(authCredentialsStoreProvider.notifier)
                  .captureSession();
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  content: Text(context.l10n.offlineRemoveAllConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(context.l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(context.l10n.delete),
                    ),
                  ],
                ),
                animationStyle: context.motionStyle,
              );
              if (confirmed != true || !context.mounted || !current()) return;
              try {
                await removeAllDownloadsFromDevice(ref);
              } finally {
                if (context.mounted && current()) {
                  ref.invalidate(offlineUsageBytesProvider);
                }
              }
            },
          ),
        ),
      ],
    ),
  ];
}

/// Standalone screen kept for the existing route; the same tiles are also
/// shown in the Downloads screen's "On-device" tab via
/// [buildOnDeviceStorageTiles].
class OfflineSettingsScreen extends ConsumerWidget {
  const OfflineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.onDeviceDownloads);
    final content = ListTileTheme(
      data: ListTileThemeData(
        subtitleTextStyle: TextStyle(
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Scaffold(
        appBar: topBar ? null : AppBar(title: title),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(children: buildOnDeviceStorageTiles(context, ref)),
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
