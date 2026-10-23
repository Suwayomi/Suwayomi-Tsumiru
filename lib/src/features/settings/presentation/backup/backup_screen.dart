// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../controller/server_controller.dart';
import '../../search/settings_search_registry.dart';
import 'widgets/automatic_backup/automatic_backup_section.dart';
import 'widgets/backup_and_restore/backup_and_restore_section.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(context, ref) {
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.backup);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(settingsProvider.future),
        child: ListTileTheme(
          data: ListTileThemeData(
            subtitleTextStyle: TextStyle(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: SettingsHighlightScope(
            child: Center(
              child: ConstrainedBox(
                constraints: settingsPageConstraints(context),
                child: ListView(
                  padding: settingsPagePadding(context),
                  children: const [
                    BackupAndRestoreSection(),
                    AutomaticBackupSection(),
                  ],
                ),
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
      child: scaffold,
    );
  }
}
