// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import 'copy_crash_log_tile.dart';

class AdvancedScreen extends ConsumerWidget {
  const AdvancedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.advanced);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: settingsPageConstraints(context),
            child: ListView(
              padding: settingsPagePadding(context),
              children: [
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'clearCache',
                      child: ListTile(
                        title: Text(context.l10n.clearCache),
                        onTap: () async {
                          // GraphQL uses an in-memory cache; only images need clearing on disk.
                          await DefaultCacheManager().emptyCache();
                          await ref
                              .read(coverCacheManagerProvider)
                              .emptyCache();
                          // Decoded covers stay in memory until restart otherwise.
                          PaintingBinding.instance.imageCache.clear();
                          PaintingBinding.instance.imageCache
                              .clearLiveImages();
                          if (context.mounted) {
                            ref
                                .read(toastProvider)
                                ?.show(context.l10n.cacheCleared);
                          }
                        },
                      ),
                    ),
                    const CopyCrashLogTile(),
                  ],
                ),
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
