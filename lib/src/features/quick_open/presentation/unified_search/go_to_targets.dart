// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../routes/router_config.dart';

/// One "jump to" destination — a screen, settings page, or category.
class GoToTarget {
  const GoToTarget({
    required this.label,
    required this.icon,
    required this.navigate,
  });

  final String Function(AppLocalizations) label;
  final IconData icon;
  final void Function(BuildContext) navigate;
}

/// Nav + settings destinations. Closures capture the exact typed-route call,
/// so this can't be const. `includeHotkeys` mirrors the desktop-only tile.
List<GoToTarget> appGoToTargets({required bool includeHotkeys}) => [
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
        label: (l) => l.general,
        icon: Icons.tune_rounded,
        navigate: (c) => const GeneralSettingsRoute().go(c),
      ),
      GoToTarget(
        label: (l) => l.appearance,
        icon: Icons.color_lens_rounded,
        navigate: (c) => const AppearanceSettingsRoute().go(c),
      ),
      GoToTarget(
        label: (l) => l.reader,
        icon: Icons.chrome_reader_mode_rounded,
        navigate: (c) => const ReaderSettingsRoute().go(c),
      ),
      if (includeHotkeys)
        GoToTarget(
          label: (l) => l.keyboardShortcuts,
          icon: Icons.keyboard_rounded,
          navigate: (c) => const HotkeysSettingsRoute().go(c),
        ),
      GoToTarget(
        label: (l) => l.backup,
        icon: Icons.settings_backup_restore_rounded,
        navigate: (c) => const BackupRoute().go(c),
      ),
      GoToTarget(
        label: (l) => l.tracking,
        icon: Icons.sync_rounded,
        navigate: (c) => const TrackingSettingsRoute().go(c),
      ),
      GoToTarget(
        label: (l) => l.server,
        icon: Icons.computer_rounded,
        navigate: (c) => const ServerSettingsRoute().go(c),
      ),
    ];

List<GoToTarget> matchGoToTargets(
  String query,
  AppLocalizations l, {
  required bool includeHotkeys,
  List<GoToTarget> extra = const [],
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    ...appGoToTargets(includeHotkeys: includeHotkeys),
    ...extra,
  ].where((t) => t.label(l).toLowerCase().contains(q)).toList();
}
