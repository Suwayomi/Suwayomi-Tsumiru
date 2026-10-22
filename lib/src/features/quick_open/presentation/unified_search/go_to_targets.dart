// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/platform/is_android_native.dart';

/// One "jump to" destination — a screen, settings page, or category.
class GoToTarget {
  const GoToTarget({
    required this.label,
    required this.icon,
    required this.navigate,
    this.subtitle,
  });

  final String Function(AppLocalizations) label;
  final IconData icon;
  final void Function(BuildContext) navigate;
  final String Function(AppLocalizations)? subtitle;
}

/// Nav + settings destinations. Closures capture the exact typed-route call,
/// so this can't be const. `includeHotkeys` mirrors the desktop-only tile,
/// `includeAccount` mirrors the More screen's Account entry.
List<GoToTarget> appGoToTargets({
  required bool includeHotkeys,
  bool includeAccount = true,
}) => [
  GoToTarget(
    label: (l) => l.library,
    icon: Icons.collections_bookmark_rounded,
    navigate: (c) => const LibraryRoute(categoryId: 0).go(c),
  ),
  GoToTarget(
    label: (l) => l.updates,
    icon: Icons.new_releases_rounded,
    navigate: (c) => const UpdatesRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.browse,
    icon: Icons.explore_rounded,
    navigate: (c) => const BrowseSourceRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.downloads,
    icon: Icons.download_rounded,
    navigate: (c) => const DownloadsRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.settings,
    icon: Icons.settings_rounded,
    navigate: (c) => const SettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.general,
    icon: Icons.tune_rounded,
    navigate: (c) => const GeneralSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.appearance,
    icon: Icons.color_lens_rounded,
    navigate: (c) => const AppearanceSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.library,
    icon: Icons.collections_bookmark_rounded,
    navigate: (c) => const LibrarySettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.downloads,
    icon: Icons.download_rounded,
    navigate: (c) => const DownloadsSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (isAndroidNative)
    GoToTarget(
      label: (l) => l.notifications,
      icon: Icons.notifications_rounded,
      navigate: (c) => const NotificationsSettingsRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.reader,
    icon: Icons.chrome_reader_mode_rounded,
    navigate: (c) => const ReaderSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (includeHotkeys)
    GoToTarget(
      label: (l) => l.keyboardShortcuts,
      icon: Icons.keyboard_rounded,
      navigate: (c) => const HotkeysSettingsRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.browse,
    icon: Icons.explore_rounded,
    navigate: (c) => const BrowseSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.backup,
    icon: Icons.settings_backup_restore_rounded,
    navigate: (c) => const BackupRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.syncyomi,
    icon: Icons.cloud_sync_rounded,
    navigate: (c) => const SyncYomiSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.koreaderSync,
    icon: Icons.menu_book_rounded,
    navigate: (c) => const KoreaderSyncSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.tracking,
    icon: Icons.sync_rounded,
    navigate: (c) => const TrackingSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.server,
    icon: Icons.computer_rounded,
    navigate: (c) => const ServerSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.connection,
    icon: Icons.dns_rounded,
    navigate: (c) => const ConnectionRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (includeAccount)
    GoToTarget(
      label: (l) => l.accountTitle,
      icon: Icons.person_rounded,
      navigate: (c) => const AccountRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.categories,
    icon: Icons.label_rounded,
    navigate: (c) => const EditCategoriesRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.extensionStores,
    icon: Icons.extension_rounded,
    navigate: (c) => const ExtensionStoreRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.about,
    icon: Icons.info_rounded,
    navigate: (c) => const AboutRoute().push(c),
    subtitle: (l) => l.settings,
  ),
];

List<GoToTarget> matchGoToTargets(
  String query,
  AppLocalizations l, {
  required bool includeHotkeys,
  bool includeAccount = true,
  List<GoToTarget> extra = const [],
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    ...appGoToTargets(
      includeHotkeys: includeHotkeys,
      includeAccount: includeAccount,
    ),
    ...extra,
  ].where((t) => t.label(l).toLowerCase().contains(q)).toList();
}
