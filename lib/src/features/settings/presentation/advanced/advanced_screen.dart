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
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../history/presentation/history_controller.dart';
import '../../../library/data/category_repository.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../manga_book/presentation/upcoming/controller/upcoming_controller.dart';
import '../../../offline/data/offline_repository.dart';
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
                    SettingsHighlightTarget(
                      id: 'removeCustomCovers',
                      child: ListTile(
                      title: Text(context.l10n.removeCustomCovers),
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(context.l10n.removeCustomCoversTitle),
                            content: Text(context.l10n.removeCustomCoversBody),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: Text(context.l10n.cancel),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: Text(context.l10n.remove),
                              ),
                            ],
                          ),
                          animationStyle: context.motionStyle,
                        );
                        if (confirmed != true || !context.mounted) return;
                        final toast = ref.read(toastProvider);
                        // The offline-filtered library can omit series, so ask the server directly.
                        final remote = await AsyncValue.guard(
                          () => ref
                              .read(categoryRepositoryProvider)
                              .getAllLibraryMangas(withFirstUnread: false),
                        );
                        if (!context.mounted) return;
                        final mangas = remote.value;
                        if (remote.hasError || mangas == null) {
                          toast?.showError(context.l10n.error);
                          return;
                        }
                        final ids = mangas
                            .where(
                              (manga) => manga.meta.any(
                                (entry) =>
                                    entry.key ==
                                        MangaMetaKeys.customCover.key &&
                                    entry.value.trim().isNotEmpty,
                              ),
                            )
                            .map((manga) => manga.id)
                            .toList();
                        if (ids.isNotEmpty) {
                          final deleted = await AsyncValue.guard(
                            () => ref
                                .read(mangaBookRepositoryProvider)
                                .deleteMangaMetas(
                                  mangaIds: ids,
                                  key: MangaMetaKeys.customCover.key,
                                ),
                          );
                          if (!context.mounted) return;
                          if (deleted.hasError) {
                            toast?.showError(context.l10n.error);
                            return;
                          }
                          final db = ref.read(offlineReadDatabaseProvider);
                          for (final id in ids) {
                            ref.invalidate(mangaWithIdProvider(mangaId: id));
                            if (db != null) {
                              await AsyncValue.guard(
                                () => db.updateMangaMetaValue(
                                  mangaId: id,
                                  key: MangaMetaKeys.customCover.key,
                                ),
                              );
                            }
                          }
                        }
                        if (!context.mounted) return;
                        ref.invalidate(libraryMangaListProvider);
                        ref.invalidate(upcomingLibraryMangasProvider);
                        ref.invalidate(readingHistoryProvider);
                        ref.invalidate(mangaReadingHistoryProvider);
                        ref.read(customCoverRevisionProvider.notifier).bump();
                        toast?.show(context.l10n.customCoversRemoved);
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
