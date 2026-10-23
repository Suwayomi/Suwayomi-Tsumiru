import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/section_title.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
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
        child: ListView(
          children: [
            SectionTitle(title: context.l10n.syncyomi),
            const SyncYomiSettingsBody(),
            SectionTitle(title: context.l10n.koreaderSync),
            const KoreaderSyncSettingsBody(),
          ],
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
