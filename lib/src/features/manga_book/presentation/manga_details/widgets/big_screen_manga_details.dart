// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/chapter_list_entry.dart';
import 'add_to_library_category.dart';
import 'chapter_list_tile.dart';
import 'manga_description.dart';
import 'missing_chapters_tile.dart';
import 'recommends_row.dart';
import 'series_info_column.dart';

class BigScreenMangaDetails extends ConsumerWidget {
  const BigScreenMangaDetails({
    super.key,
    required this.chapterList,
    required this.expansion,
    required this.manga,
    required this.mangaId,
    required this.selectedChapters,
    required this.onListRefresh,
    required this.onRefresh,
    required this.onDescriptionRefresh,
  });
  final SeriesInfoExpansion expansion;
  final MangaDto manga;
  final int mangaId;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<MangaChapterListEntry>?> chapterList;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterEntries = chapterList.value;
    final chapterCount =
        chapterEntries?.whereType<MangaChapterEntry>().length ?? 0;
    return RefreshIndicator(
      onRefresh: () => onRefresh(true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: context.isDesktop ? 55 : 1,
            child: SeriesInfoColumn(
              key: ValueKey(mangaId),
              expansion: expansion,
              builder: (expansion) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MangaDescription(
                    expansion: expansion,
                    manga: manga,
                    removeMangaFromLibrary: (() =>
                        removeMangaFromLibraryAndPurge(
                          ProviderScope.containerOf(context, listen: false),
                          mangaId,
                        )),
                    addMangaToLibrary: (() =>
                        addMangaToLibraryWithCategory(ref, context, manga)),
                    refresh: () => onDescriptionRefresh(false),
                  ),
                  if (manga.title.isNotBlank)
                    RecommendsRow(mangaId: mangaId, mangaTitle: manga.title),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 0),
          Expanded(
            flex: context.isDesktop ? 45 : 1,
            child: chapterList.showUiWhenData(context, (data) {
              if (data.isNotBlank) {
                void toggleSelect(ChapterDto val) {
                  if ((val.id).isNull) return;
                  selectedChapters.value = selectedChapters.value.toggleKey(
                    val.id,
                    val,
                  );
                }

                return Column(
                  children: [
                    ListTile(
                      title: Text(context.l10n.noOfChapters(chapterCount)),
                      trailing: context.isDesktop
                          ? IconButton(
                              tooltip: context.l10n.filter,
                              onPressed: () =>
                                  Scaffold.of(context).openEndDrawer(),
                              icon: const Icon(Icons.filter_list_rounded),
                            )
                          : null,
                    ),
                    Expanded(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          if (chapterEntries.length == index) {
                            return const ListTile();
                          }
                          final entry = chapterEntries[index];
                          return switch (entry) {
                            MangaChapterEntry() => ChapterListTile(
                              key: ValueKey('${entry.chapter.id}'),
                              manga: manga,
                              chapter: entry.chapter,
                              updateData: () => onListRefresh(false),
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
                        },
                        itemCount: chapterEntries!.length + 1,
                      ),
                    ),
                  ],
                );
              } else {
                return Emoticons(
                  title: context.l10n.noChaptersFound,
                  button: TextButton(
                    onPressed: () => onListRefresh(true),
                    child: Text(context.l10n.refresh),
                  ),
                );
              }
            }, refresh: () => onRefresh(false)),
          ),
        ],
      ),
    );
  }
}
