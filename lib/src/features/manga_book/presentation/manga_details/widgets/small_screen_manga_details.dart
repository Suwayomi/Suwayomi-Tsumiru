// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/chapter_list_entry.dart';
import '../controller/manga_details_controller.dart';
import 'add_to_library_category.dart';
import 'chapter_grid_tile.dart';
import 'chapter_list_mode_toggle.dart';
import 'chapter_list_tile.dart';
import 'manga_description.dart';
import 'missing_chapters_tile.dart';
import 'recommends_row.dart';

class SmallScreenMangaDetails extends ConsumerWidget {
  const SmallScreenMangaDetails({
    super.key,
    required this.chapterList,
    required this.manga,
    required this.selectedChapters,
    required this.mangaId,
    required this.onRefresh,
    required this.onDescriptionRefresh,
    required this.onListRefresh,
  });
  final int mangaId;
  final MangaDto manga;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<MangaChapterListEntry>?> chapterList;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterEntries = chapterList.value;
    final chapterCount =
        chapterEntries?.whereType<MangaChapterEntry>().length ?? 0;
    final listMode = ref.watch(mangaChapterListModeProvider(mangaId: mangaId));
    return RefreshIndicator(
      onRefresh: () => onRefresh(true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              child: MangaDescription(
                manga: manga,
                refresh: () => onDescriptionRefresh(false),
                removeMangaFromLibrary: () => removeMangaFromLibraryAndPurge(
                  ProviderScope.containerOf(context, listen: false),
                  mangaId,
                ),
                addMangaToLibrary: () =>
                    addMangaToLibraryWithCategory(ref, context, manga),
              ),
            ),
          ),
          if (manga.title.isNotBlank)
            SliverToBoxAdapter(
              child: RecommendsRow(mangaId: mangaId, mangaTitle: manga.title),
            ),
          SliverToBoxAdapter(
            child: ListTile(
              title: Text(context.l10n.noOfChapters(chapterCount)),
              trailing: ChapterListModeToggle(mangaId: mangaId),
            ),
          ),
          chapterList.showUiWhenData(
            context,
            (data) {
              if (data.isNotBlank) {
                void toggleSelect(ChapterDto val) {
                  if ((val.id).isNull) return;
                  selectedChapters.value = selectedChapters.value.toggleKey(
                    val.id,
                    val,
                  );
                }

                if (listMode == ChapterListMode.grid) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 64,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: chapterEntries!.length,
                      itemBuilder: (context, index) {
                        final entry = chapterEntries[index];
                        return switch (entry) {
                          MangaChapterEntry() => ChapterGridTile(
                            key: ValueKey('${entry.chapter.id}'),
                            manga: manga,
                            chapter: entry.chapter,
                            isSelected: selectedChapters.value.containsKey(
                              entry.chapter.id,
                            ),
                            canTapSelect: selectedChapters.value.isNotEmpty,
                            toggleSelect: toggleSelect,
                          ),
                          MissingChaptersEntry() => MissingChaptersGridTile(
                            key: ValueKey('missing-${entry.id}'),
                            count: entry.count,
                          ),
                        };
                      },
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = chapterEntries[index];
                    return switch (entry) {
                      MangaChapterEntry() => ChapterListTile(
                        key: ValueKey('${entry.chapter.id}'),
                        manga: manga,
                        chapter: entry.chapter,
                        updateData: () => onRefresh(false),
                        isSelected: selectedChapters.value.containsKey(
                          entry.chapter.id,
                        ),
                        canTapSelect: selectedChapters.value.isNotEmpty,
                        toggleSelect: toggleSelect,
                      ),
                      MissingChaptersEntry() => MissingChaptersListTile(
                        key: ValueKey('missing-${entry.id}'),
                        count: entry.count,
                      ),
                    };
                  }, childCount: chapterEntries!.length),
                );
              } else {
                return SliverToBoxAdapter(
                  child: Emoticons(
                    title: context.l10n.noChaptersFound,
                    button: TextButton(
                      onPressed: () => onDescriptionRefresh(true),
                      child: Text(context.l10n.refresh),
                    ),
                  ),
                );
              }
            },
            refresh: () => onRefresh(false),
            wrapper: (child) => SliverToBoxAdapter(
              child: SizedBox(height: context.height * .5, child: child),
            ),
          ),
          // Bottom spacer so the last chapter can scroll clear of the floating
          // Resume button (which otherwise permanently covers its controls).
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}
