// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/platform/is_android_native.dart';

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

List<GoToTarget> appGoToTargets({
  required bool includeHotkeys,
  bool includeAccount = true,
}) => [
  GoToTarget(
    label: (l) => l.library,
    icon: FluentIcons.library_24_regular,
    navigate: (c) => const LibraryRoute(categoryId: 0).go(c),
  ),
  GoToTarget(
    label: (l) => l.updates,
    icon: FluentIcons.news_24_regular,
    navigate: (c) => const UpdatesRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.browse,
    icon: FluentIcons.compass_northwest_24_regular,
    navigate: (c) => const BrowseSourceRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.downloads,
    icon: FluentIcons.arrow_download_24_regular,
    navigate: (c) => const DownloadsRoute().go(c),
  ),
  GoToTarget(
    label: (l) => l.settings,
    icon: FluentIcons.settings_24_regular,
    navigate: (c) => const SettingsRoute().push(c),
  ),
  GoToTarget(
    label: (l) => l.general,
    icon: FluentIcons.options_24_regular,
    navigate: (c) => const GeneralSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.appearance,
    icon: FluentIcons.color_24_regular,
    navigate: (c) => const AppearanceSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.library,
    icon: FluentIcons.library_24_regular,
    navigate: (c) => const LibrarySettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.downloads,
    icon: FluentIcons.arrow_download_24_regular,
    navigate: (c) => const DownloadsSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (isAndroidNative)
    GoToTarget(
      label: (l) => l.notifications,
      icon: FluentIcons.alert_24_regular,
      navigate: (c) => const NotificationsSettingsRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.reader,
    icon: FluentIcons.book_open_24_regular,
    navigate: (c) => const ReaderSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (includeHotkeys)
    GoToTarget(
      label: (l) => l.keyboardShortcuts,
      icon: FluentIcons.keyboard_24_regular,
      navigate: (c) => const HotkeysSettingsRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.browse,
    icon: FluentIcons.compass_northwest_24_regular,
    navigate: (c) => const BrowseSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.backup,
    icon: FluentIcons.arrow_counterclockwise_24_regular,
    navigate: (c) => const BackupRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.syncyomi,
    icon: FluentIcons.cloud_sync_24_regular,
    navigate: (c) => const SyncYomiSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.koreaderSync,
    icon: FluentIcons.book_open_24_regular,
    navigate: (c) => const KoreaderSyncSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.tracking,
    icon: FluentIcons.arrow_sync_24_regular,
    navigate: (c) => const TrackingSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.server,
    icon: FluentIcons.desktop_24_regular,
    navigate: (c) => const ServerSettingsRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.connection,
    icon: FluentIcons.server_24_regular,
    navigate: (c) => const ConnectionRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  if (includeAccount)
    GoToTarget(
      label: (l) => l.accountTitle,
      icon: FluentIcons.person_24_regular,
      navigate: (c) => const AccountRoute().push(c),
      subtitle: (l) => l.settings,
    ),
  GoToTarget(
    label: (l) => l.categories,
    icon: FluentIcons.tag_24_regular,
    navigate: (c) => const EditCategoriesRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.extensionStores,
    icon: FluentIcons.puzzle_piece_24_regular,
    navigate: (c) => const ExtensionStoreRoute().push(c),
    subtitle: (l) => l.settings,
  ),
  GoToTarget(
    label: (l) => l.about,
    icon: FluentIcons.info_24_regular,
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
