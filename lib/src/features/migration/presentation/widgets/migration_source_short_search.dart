// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/cover_row_section.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../controller/migration_controller.dart';

class MigrationSourceShortSearch extends ConsumerWidget {
  const MigrationSourceShortSearch({
    super.key,
    required this.source,
    required this.mangaList,
    this.query,
    this.onSelected,
  });

  final SourceDto source;
  final AsyncValue<List<MangaDto>> mangaList;
  final String? query;
  final ValueChanged<MangaDto>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return mangaList.when(
      data: (data) => data.isEmpty
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
                    showDarkOverlay: manga.user.inLibrary.ifNull(),
                    onPressed: () => onSelected != null
                        ? onSelected!(manga)
                        : _onMangaSelected(context, manga),
                  ),
                );
              },
            ),
      error: (_, _) => section(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                FluentIcons.error_circle_24_regular,
                size: 20,
                color: context.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.l10n.couldntReachSource(source.displayName),
                  style: TextStyle(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => ref.invalidate(
                  migrationSourceQuickSearchMangaListProvider(
                    source.id,
                    query: query,
                  ),
                ),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ),
      loading: () => section(
        child: SizedBox(
          height: mangaCoverBoxHeight(kShortSearchCoverWidth),
          child: const Center(
            child: SizedBox.square(
              dimension: 48,
              child: TsumiruShimmerIndicator(),
            ),
          ),
        ),
      ),
    );
  }

  void _onMangaSelected(BuildContext context, MangaDto targetManga) =>
      context.pop(targetManga);
}
