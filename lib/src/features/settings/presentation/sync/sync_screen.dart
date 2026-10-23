// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../koreader_sync/koreader_sync_settings_screen.dart';
import '../syncyomi/syncyomi_settings_screen.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.sync);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                const SyncYomiSettingsBody(),
                SettingsGroupHeading(label: context.l10n.koreaderSync),
                const KoreaderSyncSettingsBody(),
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
