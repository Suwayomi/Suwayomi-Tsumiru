// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/sort_list_tile.dart';
import '../controller/manga_details_controller.dart';

class MangaChapterSortTile extends ConsumerWidget {
  const MangaChapterSortTile({
    super.key,
    required this.mangaId,
    required this.sortType,
  });
  final int mangaId;
  final ChapterSort sortType;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedBy = ref.watch(
      mangaChapterSortPreferenceProvider(mangaId: mangaId),
    );
    final sortedDirection = ref.watch(
      mangaChapterSortDirectionPreferenceProvider(mangaId: mangaId),
    );
    return SortListTile(
      selected: sortType == sortedBy,
      title: Text(sortType.toLocale(context)),
      ascending: sortedDirection.ifNull(true),
      onChanged: (bool? value) => ref
          .read(
            mangaChapterSortDirectionPreferenceProvider(
              mangaId: mangaId,
            ).notifier,
          )
          .update(!(sortedDirection.ifNull())),
      onSelected: () => ref
          .read(mangaChapterSortPreferenceProvider(mangaId: mangaId).notifier)
          .update(sortType),
    );
  }
}
