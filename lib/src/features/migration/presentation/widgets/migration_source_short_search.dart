// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/cover_row_section.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../manga_book/domain/manga/manga_model.dart';

class MigrationSourceShortSearch extends StatelessWidget {
  const MigrationSourceShortSearch({
    super.key,
    required this.source,
    required this.mangaList,
    this.query,
  });

  final SourceDto source;
  final AsyncValue<List<MangaDto>> mangaList;
  final String? query;

  @override
  Widget build(BuildContext context) {
    Widget section({
      int? itemCount,
      IndexedWidgetBuilder? itemBuilder,
      Widget? child,
    }) => CoverRowSection(
      title: source.displayName,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: mangaCoverBoxHeight(kShortSearchCoverWidth),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      child: child,
    );
    return mangaList.showUiWhenData(
      context,
      (data) => data.isEmpty
          ? section(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(context.l10n.noResultFound),
              ),
            )
          : section(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final manga = data[index];
                return SizedBox(
                  width: kShortSearchCoverWidth,
                  height: mangaCoverBoxHeight(kShortSearchCoverWidth),
                  child: MangaCoverGridTile(
                    manga: manga,
                    showDarkOverlay: manga.inLibrary.ifNull(),
                    onPressed: () => _onMangaSelected(context, manga),
                  ),
                );
              },
            ),
    );
  }

  // Return the chosen target to the migration list, which sets it on the runner.
  void _onMangaSelected(BuildContext context, MangaDto targetManga) =>
      context.pop(targetManga);
}
