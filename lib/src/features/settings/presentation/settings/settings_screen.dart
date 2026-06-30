// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/crash/crash_log.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(context.l10n.general),
            leading: const Icon(Icons.tune_rounded),
            onTap: () => const GeneralSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.appearance),
            leading: const Icon(Icons.color_lens_rounded),
            onTap: () => const AppearanceSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.library),
            leading: const Icon(Icons.collections_bookmark_rounded),
            onTap: () => const LibrarySettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.downloads),
            leading: const Icon(Icons.download_rounded),
            onTap: () => const DownloadsSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.offline),
            leading: const Icon(Icons.offline_pin_rounded),
            onTap: () => const OfflineSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.reader),
            leading: const Icon(Icons.chrome_reader_mode_rounded),
            onTap: () => const ReaderSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.browse),
            leading: const Icon(Icons.explore_rounded),
            onTap: () => const BrowseSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.backup),
            leading: const Icon(Icons.settings_backup_restore_rounded),
            onTap: () => const BackupRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.tracking),
            leading: const Icon(Icons.sync_rounded),
            onTap: () => const TrackingSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.server),
            subtitle: Text(context.l10n.serverSettingsSubtitle),
            leading: const Icon(Icons.computer_rounded),
            onTap: () => const ServerSettingsRoute().go(context),
          ),
          const _CopyCrashLogTile(),
        ],
      ),
    );
  }
}

/// Lets a user grab the latest crash/error log for a bug report — it lives in
/// the app's private files dir, which they can't browse, so we copy it to the
/// clipboard. Most errors no longer show the full-screen crash page (they're
/// recoverable), so this is the way to retrieve their log after the fact.
class _CopyCrashLogTile extends ConsumerWidget {
  const _CopyCrashLogTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(context.l10n.copyCrashLog),
      subtitle: Text(context.l10n.copyCrashLogSubtitle),
      leading: const Icon(Icons.bug_report_rounded),
      onTap: () async {
        final log = readCrashLog(await initCrashLog());
        if (!context.mounted) return;
        final toast = ref.read(toastProvider);
        if (log == null) {
          toast?.show(context.l10n.noCrashLog);
          return;
        }
        await Clipboard.setData(ClipboardData(text: log));
        if (context.mounted) toast?.show(context.l10n.crashLogCopied);
      },
    );
  }
}
