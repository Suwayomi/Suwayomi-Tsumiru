// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/webui_meta/webui_settings.dart';
import '../../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../../../domain/source/source_model.dart';
import '../controller/source_manga_controller.dart';
import 'desktop_source_cover_tile.dart';

class SourceMangaGridView extends ConsumerWidget {
  const SourceMangaGridView({
    super.key,
    required this.controller,
    required this.sourceId,
    required this.sourceType,
    required this.selectedIds,
    required this.selecting,
    required this.onToggleSelection,
    required this.onAddToLibrary,
    this.addEnabled = true,
    this.source,
  });
  final PagingController<int, MangaDto> controller;
  final SourceDto? source;
  final String sourceId;
  final SourceType sourceType;
  final Set<int> selectedIds;
  final bool selecting;
  final void Function(int mangaId) onToggleSelection;
  final void Function(MangaDto manga) onAddToLibrary;
  final bool addEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagingListener(
      controller: controller,
      builder: (context, state, fetchNextPage) => PagedGridView(
        state: state.copyWith(
          pages: state.pages
              ?.map(
                (page) => visibleSourceMangas(
                  page,
                  hideLibraryEntries: ref.watch(
                    webUiBoolProvider('hideLibraryEntries'),
                  ),
                ),
              )
              .toList(),
        ),
        fetchNextPage: fetchNextPage,
        builderDelegate: PagedChildBuilderDelegate<MangaDto>(
          firstPageProgressIndicatorBuilder: (context) =>
              const CenterTsumiruShimmerIndicator(),
          newPageProgressIndicatorBuilder: (context) =>
              const CenterTsumiruShimmerIndicator(),
          firstPageErrorIndicatorBuilder: (context) => Emoticons(
            title: state.error.toString(),
            button: TextButton(
              onPressed: () => controller.refresh(),
              child: Text(context.l10n.retry),
            ),
          ),
          noItemsFoundIndicatorBuilder: (context) => Emoticons(
            title: context.l10n.noMangaFound,
            button: TextButton(
              onPressed: () => controller.refresh(),
              child: Text(context.l10n.refresh),
            ),
          ),
          itemBuilder: (context, item, index) {
            final tile = MangaCoverGridTile(
              manga: item,
              selected: selectedIds.contains(item.id),
              showSelectedCheck: !context.usesDesktopShell,
              showDarkOverlay: item.user.inLibrary.ifNull(),
              linkLocation: MangaRoute(mangaId: item.id).location,
              onLongPress: () => onToggleSelection(item.id),
              onPressed: () =>
                  selecting ||
                      (context.usesDesktopShell &&
                          AppUtils.isMultiSelectPressed())
                  ? onToggleSelection(item.id)
                  : MangaRoute(mangaId: item.id).push(context),
            );
            if (!context.usesDesktopShell) {
              return tile;
            }
            return DesktopSourceCoverTile(
              manga: item,
              selecting: selecting,
              selected: selectedIds.contains(item.id),
              onToggleSelection: () => onToggleSelection(item.id),
              onAddToLibrary: onAddToLibrary,
              addEnabled: addEnabled,
              child: tile,
            );
          },
        ),
        gridDelegate: mangaCoverGridDelegate(ref.watch(gridMinWidthProvider)),
      ),
    );
  }
}
