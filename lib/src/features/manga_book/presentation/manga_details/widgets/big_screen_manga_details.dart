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
import '../controller/manga_details_controller.dart';
import 'add_to_library_category.dart';
import 'chapter_grid_tile.dart';
import 'chapter_list_mode_toggle.dart';
import 'chapter_list_tile.dart';
import 'manga_description.dart';

class BigScreenMangaDetails extends ConsumerWidget {
  const BigScreenMangaDetails({
    super.key,
    required this.chapterList,
    required this.manga,
    required this.mangaId,
    required this.selectedChapters,
    required this.onListRefresh,
    required this.onRefresh,
    required this.onDescriptionRefresh,
  });
  final MangaDto manga;
  final int mangaId;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<ChapterDto>?> chapterList;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredChapterList = chapterList.value;
    return RefreshIndicator(
      onRefresh: () => onRefresh(true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: MangaDescription(
                manga: manga,
                removeMangaFromLibrary: (() =>
                    removeMangaFromLibraryAndPurge(ref, mangaId)),
                addMangaToLibrary: (() =>
                    addMangaToLibraryWithCategory(ref, context, mangaId)),
                refresh: () => onDescriptionRefresh(false),
              ),
            ),
          ),
          const VerticalDivider(width: 0),
          Expanded(
            child: chapterList.showUiWhenData(
              context,
              (data) {
                if (data.isNotBlank) {
                  final listMode = ref
                      .watch(mangaChapterListModeProvider(mangaId: mangaId));
                  void toggleSelect(ChapterDto val) {
                    if ((val.id).isNull) return;
                    selectedChapters.value =
                        selectedChapters.value.toggleKey(val.id, val);
                  }

                  return Column(
                    children: [
                      // The body extends behind the transparent app bar (hero
                      // blur); without this the chapter header sits under it.
                      if (selectedChapters.value.isEmpty)
                        SizedBox(
                          height: MediaQuery.paddingOf(context).top +
                              kToolbarHeight,
                        ),
                      ListTile(
                        title: Text(context.l10n.noOfChapters(
                          filteredChapterList?.length ?? 0,
                        )),
                        trailing: ChapterListModeToggle(mangaId: mangaId),
                      ),
                      Expanded(
                        child: listMode == ChapterListMode.grid
                            ? GridView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 80),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 64,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                ),
                                itemCount: filteredChapterList!.length,
                                itemBuilder: (context, index) =>
                                    ChapterGridTile(
                                  key: ValueKey(
                                      "${filteredChapterList[index].id}"),
                                  manga: manga,
                                  chapter: filteredChapterList[index],
                                  isSelected: selectedChapters.value
                                      .containsKey(
                                          filteredChapterList[index].id),
                                  canTapSelect:
                                      selectedChapters.value.isNotEmpty,
                                  toggleSelect: toggleSelect,
                                ),
                              )
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  if (filteredChapterList.length == index) {
                                    return const ListTile();
                                  }
                                  final key = ValueKey(
                                      "${filteredChapterList[index].id}");
                                  final chapter = filteredChapterList[index];
                                  return ChapterListTile(
                                    key: key,
                                    manga: manga,
                                    chapter: chapter,
                                    updateData: () => onListRefresh(false),
                                    isSelected: selectedChapters.value
                                        .containsKey(chapter.id),
                                    canTapSelect:
                                        selectedChapters.value.isNotEmpty,
                                    toggleSelect: toggleSelect,
                                  );
                                },
                                itemCount: filteredChapterList!.length + 1,
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
              },
              refresh: () => onRefresh(false),
            ),
          ),
        ],
      ),
    );
  }
}
