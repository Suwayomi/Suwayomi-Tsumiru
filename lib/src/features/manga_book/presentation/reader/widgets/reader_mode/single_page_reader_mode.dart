// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_constants.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/cache_manager_extensions.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../controller/reader_settings_model.dart';
import '../../utils/reader_initial_page.dart';
import '../reader_wrapper.dart';
import 'infinity_continuous/infinity_continuous_feedback.dart';
import 'paged_reader_viewport.dart';
import 'paged_spread_mapping.dart';

/// "Animate page transitions": paged next/prev animate over
/// [kDuration] when ON, else jump instantly ([kInstantDuration]).
Duration pagedNavDuration({required bool animate}) =>
    animate ? kDuration : kInstantDuration;

class SinglePageReaderMode extends HookConsumerWidget {
  const SinglePageReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    this.onPageChanged,
    this.reverse = false,
    this.scrollDirection = Axis.horizontal,
    this.showReaderLayoutAnimation = false,
    this.effectiveReaderMode,
    this.openAtEnd = false,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ValueSetter<int>? onPageChanged;
  final bool reverse;
  final Axis scrollDirection;
  final bool showReaderLayoutAnimation;
  final ReaderMode? effectiveReaderMode;
  final bool openAtEnd;
  final ChapterPagesDto chapterPages;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheManager = useMemoized(() => DefaultCacheManager());
    final controller = useMemoized(() => PagedReaderController());
    final settings = ref.watch(readerEffectiveSettingsProvider(manga.id));

    final pageLayout = settings.pageLayout;
    final trueDual = settings.trueDualPageSpread;
    final splitWide = settings.dualPageSplitPaged;
    final splitInvert = settings.dualPageInvertPaged;
    final invertDouble = settings.invertDoublePages;
    final centerMargin = settings.centerMarginType;
    final isLandscape = context.width > context.height;
    final isHorizontal = scrollDirection == Axis.horizontal;
    final wantDouble = isHorizontal &&
        (pageLayout == PageLayout.doublePages ||
            (pageLayout == PageLayout.automatic && isLandscape) ||
            trueDual);

    final widePages = useState(<int>{});
    bool isWide(int raw) => widePages.value.contains(raw);
    final mapping = useMemoized(
      () => buildSpreadMapping(
        pageCount: chapterPages.pages.length,
        doublePages: wantDouble,
        splitWide: splitWide && isHorizontal,
        splitInvert: splitInvert,
        isWide: isWide,
      ),
      [
        chapterPages.pages.length,
        wantDouble,
        splitWide,
        splitInvert,
        isHorizontal,
        widePages.value,
      ],
    );

    final initialRaw = readerInitialPageIndex(
      chapter: chapter,
      chapterPages: chapterPages,
      openAtEnd: openAtEnd,
    );
    final initialDisplay = mapping.rawToDisplay(initialRaw);
    final currentIndex = useState(initialRaw);

    useEffect(() {
      onPageChanged?.call(currentIndex.value);
      if (chapterPages.pages.isNotEmpty) {
        final currentPage = currentIndex.value;
        for (final page in {
          currentPage - 1,
          currentPage + 1,
          currentPage + 2
        }) {
          if (page >= 0 && page < chapterPages.pages.length) {
            cacheManager.getServerFile(ref, chapterPages.pages[page]);
          }
        }
      }
      return null;
    }, [currentIndex.value, chapterPages.pages.length]);

    void onPageWide(int raw, bool wide) {
      if (!wide || widePages.value.contains(raw)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || widePages.value.contains(raw)) return;
        widePages.value = {...widePages.value, raw};
      });
    }

    final (pageFit, pageSize) =
        settings.imageScaleType.pagedFit(context.width, context.height);
    final reversePair = invertDouble != reverse;
    final spreadPageIndexes = _spreadPageIndexes(
      mapping,
      currentIndex.value,
      reversePair: reversePair,
    );
    final showChapterTransition = settings.alwaysShowChapterTransition;
    final wrapperReaderMode =
        effectiveReaderMode ?? _singlePageReaderMode(scrollDirection, reverse);

    return ReaderWrapper(
      scrollDirection: scrollDirection,
      chapter: chapter,
      manga: manga,
      chapterPages: chapterPages,
      currentIndex: currentIndex.value,
      onChanged: controller.jumpToRaw,
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      onPrevious: controller.previous,
      onNext: controller.next,
      childHandlesGestures: true,
      isAtFirstBoundary: () => controller.isAtFirst,
      isAtLastBoundary: () => controller.isAtLast,
      spreadPageIndexes: spreadPageIndexes,
      effectiveReaderMode: wrapperReaderMode,
      child: PagedReaderViewport(
        controller: controller,
        mapping: mapping,
        pages: chapterPages.pages,
        initialDisplayIndex: initialDisplay,
        axis: scrollDirection,
        reverse: reverse,
        animateTransitions: settings.animatePageTransitions,
        pageFit: pageFit,
        pageSize: pageSize,
        centerMargin: centerMargin,
        rotateWide: settings.rotateWidePages,
        rotateWideInvert: settings.rotateWideInvert,
        reversePair: reversePair,
        cropBorders: settings.cropBorders,
        onPageWide: onPageWide,
        onRawPageChanged: (raw) {
          if (raw == currentIndex.value) return;
          currentIndex.value = raw;
        },
        pinchEnabled: settings.pinchToZoom,
        doubleTapToZoom: settings.doubleTapToZoom,
        disableZoomIn: false,
        disableZoomOut: settings.disableZoomOut,
        navigateToPan: settings.navigateToPan,
        previousBoundary: showChapterTransition
            ? _PagedChapterTransition(
                chapterName: chapter.name,
                isChapterStart: true,
              )
            : null,
        nextBoundary: showChapterTransition
            ? _PagedChapterTransition(
                chapterName: chapter.name,
                isChapterStart: false,
              )
            : null,
      ),
    );
  }

  List<int>? _spreadPageIndexes(
    SpreadMapping mapping,
    int currentRaw, {
    required bool reversePair,
  }) {
    if (mapping.isEmpty) return null;
    final entry = mapping.entries[mapping.rawToDisplay(currentRaw)];
    final second = entry.second;
    if (second == null || second.raw == entry.first.raw) return null;
    final ordered = reversePair
        ? [second.raw, entry.first.raw]
        : [entry.first.raw, second.raw];
    return ordered;
  }
}

ReaderMode _singlePageReaderMode(Axis axis, bool reverse) {
  if (axis == Axis.vertical) return ReaderMode.singleVertical;
  return reverse
      ? ReaderMode.singleHorizontalRTL
      : ReaderMode.singleHorizontalLTR;
}

class _PagedChapterTransition extends StatelessWidget {
  const _PagedChapterTransition({
    required this.chapterName,
    required this.isChapterStart,
  });

  final String chapterName;
  final bool isChapterStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: InfinityContinuousChapterSeparator(
          chapterName: chapterName,
          isChapterStart: isChapterStart,
        ),
      ),
    );
  }
}
