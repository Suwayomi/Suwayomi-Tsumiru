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

/// The scrollable that renders one library tab's manga, shared by the
/// per-category list and the grouped tabs.
class LibraryMangaGridView extends StatelessWidget {
  const LibraryMangaGridView({
    super.key,
    required this.items,
    required this.onOpen,
    this.onLongPress,
    this.selection = const {},
  });

  final List<MangaDto> items;
  final void Function(MangaDto manga) onOpen;
  final void Function(MangaDto manga)? onLongPress;

  /// Ids of the currently multi-selected manga (empty when not selecting).
  final Set<int> selection;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          LibraryMangaSliver(
            items: items,
            onOpen: onOpen,
            onLongPress: onLongPress,
            selection: selection,
          ),
        ],
      );
}

/// The sliver that lays [items] out under the active [DisplayMode] and
/// [LibraryGridStyle].
///
/// Sliver-shaped so the section-headers group style can stack one per group in
/// a single [CustomScrollView] and stay lazy — a shrink-wrapped inner viewport
/// per group would build every tile in the library on every frame.
class LibraryMangaSliver extends ConsumerWidget {
  const LibraryMangaSliver({
    super.key,
    required this.items,
    required this.onOpen,
    this.onLongPress,
    this.selection = const {},
  });

  final List<MangaDto> items;
  final void Function(MangaDto manga) onOpen;
  final void Function(MangaDto manga)? onLongPress;

  /// Ids of the currently multi-selected manga (empty when not selecting).
  final Set<int> selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final gridStyle =
        ref.watch(libraryGridStyleKeyProvider) ?? LibraryGridStyle.uniform;
    final outlineOnCovers = ref.watch(outlineOnCoversProvider).ifNull(true);
    final limitTitleLines = ref.watch(limitTitleLinesProvider).ifNull(true);
    final listScale = ref.watch(libraryListScaleProvider) ??
        DBKeys.listScale.initial as double;
    final gridWidth = ref.watch(gridMinWidthProvider) ??
        DBKeys.gridMangaCoverWidth.initial as double;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fixedCols = (isLandscape
            ? ref.watch(libraryLandscapeColumnsProvider)
            : ref.watch(libraryPortraitColumnsProvider)) ??
        0;

    final showContinueReading =
        ref.watch(showContinueReadingButtonProvider).ifNull(false);
    final selecting = selection.isNotEmpty;
    VoidCallback? continueReadingFor(MangaDto manga) {
      // While multi-selecting, taps belong to the selection.
      if (!showContinueReading || selecting) return null;
      final chapter = manga.firstUnreadChapter;
      if (chapter == null) return null;
      return () {
        unawaited(() async {
          // Warm the chapter list first so the reader opens on real data.
          await AsyncValue.guard(
            () => ref.read(mangaChapterListProvider(mangaId: manga.id).future),
          );
          if (!context.mounted) return;
          ReaderRoute(mangaId: manga.id, chapterId: chapter.id).push(context);
        }());
      };
    }

    // Uniform grids need a SliverGridDelegate — one fixed main-axis extent for
    // every tile. The user's column count, or Auto (width-based).
    SliverGridDelegate uniformDelegate({bool titleBelow = false}) =>
        fixedCols > 0
            ? MangaCoverFixedCountGridDelegate(
                crossAxisCount: fixedCols,
                crossAxisSpacing: 2.0,
                mainAxisSpacing: 2.0,
                titleExtent: titleBelow ? kGridTitleExtent : 0.0,
              )
            : mangaCoverGridDelegate(gridWidth, titleBelow: titleBelow);

    // Freeform layouts take a SliverSimpleGridDelegate instead: it only decides
    // the cross-axis split and leaves each tile's height to the tile.
    SliverSimpleGridDelegate freeformDelegate() => fixedCols > 0
        ? SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: fixedCols,
          )
        : SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: gridWidth,
          );

    // Preserves element state across re-orders for slivers that recalculate
    // layout offsets. Built once per build() (items.length lookups worth of
    // work) instead of doing an O(items.length) indexWhere scan inside the
    // callback itself — the callback is invoked once per child needing
    // relocation, so a linear scan there turns a single reorder into an
    // O(n^2) pass over the whole visible+cached range.
    final idToIndex = {for (var i = 0; i < items.length; i++) items[i].id: i};
    int? findChildIndex(Key key) => idToIndex[(key as ValueKey<int>).value];

    // Re-keys masonry on item order changes to prevent crashes from nulled child offsets.
    Key masonryOrderKey() => ValueKey(Object.hashAll(items.map((m) => m.id)));

    Widget grid({bool titleBelow = false, bool showTitle = true}) {
      Widget tile(BuildContext context, int index) {
        final manga = items[index];
        return MangaCoverGridTile(
          key: ValueKey<int>(manga.id),
          manga: manga,
          selected: selection.contains(manga.id),
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
        // Rows are as tall as their tallest cover and tiles bottom-align inside them.
        LibraryGridStyle.nonUniform => SliverAlignedGrid(
            gridDelegate: freeformDelegate(),
            itemCount: items.length,
            itemBuilder: tile,
            mainAxisSpacing: 2.0,
            crossAxisSpacing: 2.0,
          ),
        // Masonry: independent column packing. Re-keyed on item order instead of moving children.
        LibraryGridStyle.staggered => SliverMasonryGrid(
            key: masonryOrderKey(),
            gridDelegate: freeformDelegate(),
            delegate: SliverChildBuilderDelegate(
              tile,
              childCount: items.length,
            ),
            mainAxisSpacing: 2.0,
            crossAxisSpacing: 2.0,
          ),
      };
    }

    // Rows scale as one unit: the tile scales its cover box, this scales the
    // text inside it.
    Widget scaled(Widget child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: _listTextScaler(context, listScale),
          ),
          child: child,
        );

    // Row extents track the same composed factor as the text inside them: the
    // shipped 96/176 were tuned at scale 1.0.
    final rowScale =
        listScale * (MediaQuery.textScalerOf(context).scale(14) / 14);

    // A fixed extent lets the viewport map offset to index without laying
    // anything out, but an uncapped title has to be able to push its own row
    // taller — as does the descriptive row, whose contents vary regardless.
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

    return switch (displayMode) {
      DisplayMode.list || null => listSliver(
          extent: 96 * rowScale,
          builder: (context, index) => scaled(MangaCoverListTile(
            key: ValueKey<int>(items[index].id),
            manga: items[index],
            selected: selection.contains(items[index].id),
            onPressed: () => onOpen(items[index]),
            onLongPress:
                onLongPress == null ? null : () => onLongPress!(items[index]),
            onContinueReading: continueReadingFor(items[index]),
            showCountBadges: true,
            scale: listScale,
            limitTitleLines: limitTitleLines,
          )),
        ),
      DisplayMode.descriptiveList => listSliver(
          extent: 176 * rowScale,
          fixedExtent: false,
          builder: (context, index) => scaled(MangaCoverDescriptiveListTile(
            key: ValueKey<int>(items[index].id),
            manga: items[index],
            selected: selection.contains(items[index].id),
            onPressed: () => onOpen(items[index]),
            onLongPress:
                onLongPress == null ? null : () => onLongPress!(items[index]),
            onContinueReading: continueReadingFor(items[index]),
            showBadges: true,
            outlineOnCovers: outlineOnCovers,
            scale: listScale,
            titleMaxLines: limitTitleLines ? 2 : null,
          )),
        ),
      DisplayMode.grid => grid(),
      DisplayMode.comfortableGrid => grid(titleBelow: true),
      DisplayMode.coverOnly => grid(showTitle: false),
    };
  }
}

/// The library list scale composed with the platform text scale. [TextScaler]
/// has no compose operation, so the platform scaler is linearised around 14sp
/// rather than overriding the user's font preference outright.
TextScaler _listTextScaler(BuildContext context, double scale) {
  final platform = MediaQuery.textScalerOf(context).scale(14) / 14;
  return TextScaler.linear(platform * scale);
}
