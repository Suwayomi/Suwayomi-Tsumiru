// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../../settings/presentation/appearance/widgets/grid_cover_width_slider/grid_cover_width_slider.dart';
import '../controller/library_controller.dart';

class LibraryMangaGridView extends StatelessWidget {
  const LibraryMangaGridView({
    super.key,
    required this.items,
    required this.onOpen,
    this.onLongPress,
    this.selection = const {},
    this.linkLocationFor,
  });

  final List<MangaDto> items;
  final void Function(MangaDto manga) onOpen;
  final void Function(MangaDto manga)? onLongPress;

  final Set<int> selection;

  final String? Function(MangaDto manga)? linkLocationFor;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      LibraryMangaSliver(
        items: items,
        onOpen: onOpen,
        onLongPress: onLongPress,
        selection: selection,
        linkLocationFor: linkLocationFor,
      ),
    ],
  );
}

/// Slivers keep grouped sections lazy; shrink-wrapped inner viewports would build every tile.
class LibraryMangaSliver extends ConsumerWidget {
  const LibraryMangaSliver({
    super.key,
    required this.items,
    required this.onOpen,
    this.onLongPress,
    this.selection = const {},
    this.linkLocationFor,
  });

  final List<MangaDto> items;
  final void Function(MangaDto manga) onOpen;
  final void Function(MangaDto manga)? onLongPress;

  final Set<int> selection;

  final String? Function(MangaDto manga)? linkLocationFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final gridStyle =
        ref.watch(libraryGridStyleKeyProvider) ?? LibraryGridStyle.uniform;
    final outlineOnCovers = ref.watch(outlineOnCoversProvider).ifNull(true);
    final limitTitleLines = ref.watch(limitTitleLinesProvider).ifNull(true);
    final listScale =
        ref.watch(libraryListScaleProvider) ??
        DBKeys.listScale.initial as double;
    final gridWidth =
        ref.watch(gridMinWidthProvider) ??
        DBKeys.gridMangaCoverWidth.initial as double;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fixedCols =
        (isLandscape
            ? ref.watch(libraryLandscapeColumnsProvider)
            : ref.watch(libraryPortraitColumnsProvider)) ??
        0;

    final showContinueReading = ref
        .watch(showContinueReadingButtonProvider)
        .ifNull(false);
    final selecting = selection.isNotEmpty;
    VoidCallback? continueReadingFor(MangaDto manga) {
      if (!showContinueReading || selecting) return null;
      final chapter = manga.user.firstUnreadChapter;
      if (chapter == null) return null;
      return () {
        unawaited(() async {
          // Warm chapters before opening so the reader has real data.
          await AsyncValue.guard(
            () => ref.read(mangaChapterListProvider(mangaId: manga.id).future),
          );
          if (!context.mounted) return;
          ReaderRoute(mangaId: manga.id, chapterId: chapter.id).push(context);
        }());
      };
    }

    SliverGridDelegate uniformDelegate({bool titleBelow = false}) =>
        mangaCoverUniformGridDelegate(
          gridWidth,
          fixedCols,
          titleBelow: titleBelow,
        );

    SliverSimpleGridDelegate freeformDelegate() => fixedCols > 0
        ? SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: fixedCols,
          )
        : SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: gridWidth,
          );

    // Precompute indices to preserve child state without O(n²) reorder lookups.
    final idToIndex = {for (var i = 0; i < items.length; i++) items[i].id: i};
    int? findChildIndex(Key key) => idToIndex[(key as ValueKey<int>).value];

    // Masonry cannot relocate children with null offsets; re-key when item order changes.
    Key masonryOrderKey() => ValueKey(Object.hashAll(items.map((m) => m.id)));

    Widget grid({bool titleBelow = false, bool showTitle = true}) {
      Widget tile(BuildContext context, int index) {
        final manga = items[index];
        return MangaCoverGridTile(
          key: ValueKey<int>(manga.id),
          manga: manga,
          selected: selection.contains(manga.id),
          linkLocation:
              linkLocationFor?.call(manga) ??
              MangaRoute(mangaId: manga.id).location,
          onPressed: () => onOpen(manga),
          onLongPress: onLongPress == null ? null : () => onLongPress!(manga),
          onContinueReading: continueReadingFor(manga),
          showCountBadges: true,
          showTitle: showTitle,
          titleBelow: titleBelow,
          showDarkOverlay: false,
          gridStyle: gridStyle,
          outlineOnCovers: outlineOnCovers,
          limitTitleLines: limitTitleLines,
        );
      }

      return switch (gridStyle) {
        LibraryGridStyle.uniform => SliverGrid(
          gridDelegate: uniformDelegate(titleBelow: titleBelow),
          delegate: SliverChildBuilderDelegate(
            tile,
            childCount: items.length,
            findChildIndexCallback: findChildIndex,
          ),
        ),
        LibraryGridStyle.nonUniform => SliverAlignedGrid(
          gridDelegate: freeformDelegate(),
          itemCount: items.length,
          itemBuilder: tile,
          mainAxisSpacing: 2.0,
          crossAxisSpacing: 2.0,
        ),
        LibraryGridStyle.staggered => SliverMasonryGrid(
          key: masonryOrderKey(),
          gridDelegate: freeformDelegate(),
          delegate: SliverChildBuilderDelegate(tile, childCount: items.length),
          mainAxisSpacing: 2.0,
          crossAxisSpacing: 2.0,
        ),
      };
    }

    Widget scaled(Widget child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: _listTextScaler(context, listScale)),
      child: child,
    );

    // Row extents 96/176 are calibrated at scale 1.0.
    final rowScale =
        listScale * (MediaQuery.textScalerOf(context).scale(14) / 14);

    // Uncapped titles and descriptive content require variable row heights.
    Widget listSliver({
      required double extent,
      required NullableIndexedWidgetBuilder builder,
      bool fixedExtent = true,
    }) {
      final delegate = SliverChildBuilderDelegate(
        builder,
        childCount: items.length,
        findChildIndexCallback: findChildIndex,
      );
      return fixedExtent && limitTitleLines
          ? SliverFixedExtentList(itemExtent: extent, delegate: delegate)
          : SliverList(delegate: delegate);
    }

    final sliver = switch (displayMode) {
      DisplayMode.list || null => listSliver(
        extent: 96 * rowScale,
        builder: (context, index) => scaled(
          MangaCoverListTile(
            key: ValueKey<int>(items[index].id),
            manga: items[index],
            selected: selection.contains(items[index].id),
            linkLocation:
                linkLocationFor?.call(items[index]) ??
                MangaRoute(mangaId: items[index].id).location,
            onPressed: () => onOpen(items[index]),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(items[index]),
            onContinueReading: continueReadingFor(items[index]),
            showCountBadges: true,
            scale: listScale,
            limitTitleLines: limitTitleLines,
          ),
        ),
      ),
      DisplayMode.descriptiveList => listSliver(
        extent: 176 * rowScale,
        fixedExtent: false,
        builder: (context, index) => scaled(
          MangaCoverDescriptiveListTile(
            key: ValueKey<int>(items[index].id),
            manga: items[index],
            selected: selection.contains(items[index].id),
            linkLocation:
                linkLocationFor?.call(items[index]) ??
                MangaRoute(mangaId: items[index].id).location,
            onPressed: () => onOpen(items[index]),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(items[index]),
            onContinueReading: continueReadingFor(items[index]),
            showBadges: true,
            outlineOnCovers: outlineOnCovers,
            scale: listScale,
            titleMaxLines: limitTitleLines ? 2 : null,
          ),
        ),
      ),
      DisplayMode.grid => grid(),
      DisplayMode.comfortableGrid => grid(titleBelow: true),
      DisplayMode.coverOnly => grid(showTitle: false),
    };
    // Reserve scrollbar clearance inside the desktop sliver so covers stay left of the thumb.
    if (!context.usesDesktopShell) return sliver;
    return SliverPadding(
      padding: const EdgeInsets.only(right: kDesktopScrollbarGutter),
      sliver: sliver,
    );
  }
}

/// Composes list scale with platform text scale, linearized at 14sp because TextScaler has no compose.
TextScaler _listTextScaler(BuildContext context, double scale) {
  final platform = MediaQuery.textScalerOf(context).scale(14) / 14;
  return TextScaler.linear(platform * scale);
}
