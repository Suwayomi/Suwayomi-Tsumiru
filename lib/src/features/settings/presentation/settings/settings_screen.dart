// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/crash/copy_crash_log.dart';
import '../../../../utils/crash/crash_log.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/platform/platform_runtime.dart';

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
            // On-device (offline) downloads are now the "On-device" tab inside
            // this screen, so there's no separate "Offline" entry.
            onTap: () => const DownloadsSettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.reader),
            leading: const Icon(Icons.chrome_reader_mode_rounded),
            onTap: () => const ReaderSettingsRoute().go(context),
          ),
          if (isKeyboardRuntime)
            ListTile(
              title: Text(context.l10n.keyboardShortcuts),
              leading: const Icon(Icons.keyboard_rounded),
              onTap: () => const HotkeysSettingsRoute().go(context),
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
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: context.l10n.clearCrashLog,
        onPressed: () async {
          clearCrashLog(await initCrashLog());
          if (context.mounted) {
            ref.read(toastProvider)?.show(context.l10n.crashLogCleared);
          }
        },
      ),
      onTap: () async {
        final log = crashLogForClipboard(await initCrashLog());
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
