// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../widgets/section_title.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import '../data/offline_settings_providers.dart';
import 'offline_server_mismatch_banner.dart';
import 'offline_settings_format.dart';

/// The on-device (offline) download + storage settings, as a flat list of tiles
/// so it can be composed into the Downloads screen's "On-device" tab. Returns a
/// single "not available" note when the offline feature is disabled.
List<Widget> buildOnDeviceStorageTiles(BuildContext context, WidgetRef ref) {
  if (!ref.watch(offlineEnabledProvider)) {
    return [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.l10n.offlineNotAvailable),
      ),
    ];
  }
  return [
    const OfflineServerMismatchBanner(showAfterDismissal: true),
    SectionTitle(title: context.l10n.offlineStorageSection),
    ListTile(
      title: Text(context.l10n.offlineStorageUsage),
      subtitle: Text(
        formatBytes(ref.watch(offlineUsageBytesProvider).value ?? 0),
      ),
    ),
    ListTile(
      title: Text(context.l10n.offlineRemoveAllDownloads),
      onTap: () async {
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
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        final db = ref.read(offlineDatabaseProvider);
        try {
          for (final m in await db.libraryManga()) {
            for (final ch in await db.downloadedChaptersForManga(m.id)) {
              try {
                await deleteChapterFromDevice(ref, ch.id);
              } catch (_) {}
            }
          }
        } finally {
          ref.invalidate(offlineUsageBytesProvider);
        }
      },
    ),
    SectionTitle(title: context.l10n.offlineDownloadsSection),
    SettingsPropTile(
      title: context.l10n.downloadOverWifiOnly,
      type: SettingsPropType.switchTile(
        value: ref.watch(offlineWifiOnlyProvider) ?? true,
        onChanged: (v) async {
          ref.read(offlineWifiOnlyProvider.notifier).update(v);
          return null;
        },
      ),
    ),
    SettingsPropTile(
      title: context.l10n.offlineConcurrencyLabel,
      subtitle: context.l10n.offlineConcurrencyValue(
          ref.watch(offlineDownloadConcurrencyProvider) ?? 2),
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
    SectionTitle(title: context.l10n.offlineSafetyNets),
    SettingsPropTile(
      title: context.l10n.offlineStorageCapEnable,
      type: SettingsPropType.switchTile(
        value: ref.watch(offlineStorageCapEnabledProvider) ?? false,
        onChanged: (v) async {
          ref.read(offlineStorageCapEnabledProvider.notifier).update(v);
          return null;
        },
      ),
    ),
    SettingsPropTile(
      title: context.l10n.offlineStorageCapLimit,
      subtitle: context.l10n
          .offlineMegabytes(ref.watch(offlineStorageCapMbProvider) ?? 2000),
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
    SettingsPropTile(
      title: context.l10n.offlineTimeEvictEnable,
      type: SettingsPropType.switchTile(
        value: ref.watch(offlineTimeEvictEnabledProvider) ?? false,
        onChanged: (v) async {
          ref.read(offlineTimeEvictEnabledProvider.notifier).update(v);
          return null;
        },
      ),
    ),
    SettingsPropTile(
      title: context.l10n.offlineKeepDaysLabel,
      subtitle:
          context.l10n.offlineDays(ref.watch(offlineKeepDaysProvider) ?? 30),
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
  ];
}

/// Standalone screen kept for the existing route; the same tiles are also shown
/// in the Downloads screen's "On-device" tab via [buildOnDeviceStorageTiles].
class OfflineSettingsScreen extends ConsumerWidget {
  const OfflineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTileTheme(
      data: const ListTileThemeData(
        subtitleTextStyle: TextStyle(color: Colors.grey),
      ),
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.onDeviceDownloads)),
        body: ListView(children: buildOnDeviceStorageTiles(context, ref)),
      ),
    );
  }
}
