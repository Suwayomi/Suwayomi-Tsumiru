// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_constants.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/cache_manager_extensions.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../../../widgets/server_image.dart';
import '../../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../reader_wrapper.dart';
import 'double_page_view.dart';
import 'paged_spread_mapping.dart';
import 'reader_zoom_view.dart';
import 'rotate_wide_page.dart';

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
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ValueSetter<int>? onPageChanged;
  final bool reverse;
  final Axis scrollDirection;
  final bool showReaderLayoutAnimation;
  final ChapterPagesDto chapterPages;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheManager = useMemoized(() => DefaultCacheManager());

    // --- Page composition settings (double-page / dual-split). ---
    // Double-page pairing is a HORIZONTAL-paged feature only (paged viewer).
    // pageLayout automatic → double in landscape, single in portrait.
    final pageLayout = ref.read(pageLayoutKeyProvider) ?? PageLayout.automatic;
    final trueDual = ref.read(trueDualPageSpreadProvider).ifNull();
    final splitWide = ref.read(dualPageSplitPagedProvider).ifNull();
    final splitInvert = ref.read(dualPageInvertPagedProvider).ifNull();
    final invertDouble = ref.read(invertDoublePagesProvider).ifNull();
    final centerMargin =
        ref.read(centerMarginTypeKeyProvider) ?? CenterMarginType.none;
    final isLandscape = context.width > context.height;
    final isHorizontal = scrollDirection == Axis.horizontal;
    final wantDouble = isHorizontal &&
        (pageLayout == PageLayout.doublePages ||
            (pageLayout == PageLayout.automatic && isLandscape) ||
            trueDual);
    // Composite render path: only when the layout actually changes what a
    // PageView item is. Otherwise the OFF path below is byte-identical.
    final composite = wantDouble || (splitWide && isHorizontal);

    // Wide-page cache — a page joins as its image resolves ([onPageWide]).
    final widePages = useState(const <int>{});
    bool isWide(int raw) => widePages.value.contains(raw);

    // Build the display list (pairs / split halves). Null on the OFF path.
    final mapping = composite
        ? buildSpreadMapping(
            pageCount: chapterPages.pages.length,
            doublePages: wantDouble,
            splitWide: splitWide && isHorizontal,
            splitInvert: splitInvert,
            isWide: isWide,
          )
        : null;

    // Latest mapping, read by the (once-bound) scroll listener below. The
    // listener effect can't re-bind on every mapping change (a wide page
    // resolving keeps it non-null), so it would otherwise translate the new
    // display position through a stale mapping and mis-report the raw page.
    final mappingRef = useRef(mapping);
    mappingRef.value = mapping;

    // currentIndex is ALWAYS the RAW page (read-tracking + seekbar contract).
    final initialRaw = chapter.isRead.ifNull()
        ? 0
        : chapter.lastPageRead.getValueOnNullOrNegative();
    final initialDisplay =
        mapping == null ? initialRaw : mapping.rawToDisplay(initialRaw);
    final scrollController = usePageController(initialPage: initialDisplay);
    final currentIndex = useState(initialRaw);

    useEffect(() {
      if (onPageChanged != null) onPageChanged!(currentIndex.value);
      int currentPage = currentIndex.value;
      // Only prefetch if we have pages data
      if (chapterPages.pages.isNotEmpty) {
        // Prev page
        if (currentPage > 0 && currentPage - 1 < chapterPages.pages.length) {
          cacheManager.getServerFile(
            ref,
            chapterPages.pages[currentPage - 1],
          );
        }
        // Next page
        if (currentPage < (chapterPages.pages.length - 1)) {
          cacheManager.getServerFile(
            ref,
            chapterPages.pages[currentPage + 1],
          );
        }
        // 2nd next page
        if (currentPage < (chapterPages.pages.length - 2)) {
          cacheManager.getServerFile(
            ref,
            chapterPages.pages[currentPage + 2],
          );
        }
      }
      return null;
    }, [currentIndex.value, chapterPages.pages.length]);
    useEffect(() {
      listener() {
        final currentPage = scrollController.page;
        if (currentPage == null) return;
        // Translate the controller's DISPLAY position back to a raw page, always
        // through the latest mapping (see [mappingRef]).
        final currentMapping = mappingRef.value;
        currentIndex.value = currentMapping == null
            ? currentPage.toInt()
            : currentMapping.displayToRaw(currentPage.toInt());
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);
    // Re-anchor when the display list reshapes (a wide page resolved, or the
    // composite/orientation flipped) so the current RAW page stays put — the
    // seekbar/tracking never jump even as the item layout shifts.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        final target = mapping == null
            ? currentIndex.value
            : mapping.rawToDisplay(currentIndex.value);
        if (scrollController.page?.round() != target) {
          scrollController.jumpToPage(target);
        }
      });
      return null;
    }, [composite, widePages.value]);

    // Reports a page's aspect the first time its image resolves; a wide page
    // then isolates/splits on the next build. Deferred to dodge build-phase
    // writes; aspect is stable so we only ever add.
    void onPageWide(int raw, bool wide) {
      if (!wide || widePages.value.contains(raw)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || widePages.value.contains(raw)) return;
        widePages.value = {...widePages.value, raw};
      });
    }

    // "Animate page transitions": animate next/prev when ON, else jump.
    final isAnimationEnabled =
        ref.read(animatePageTransitionsProvider).ifNull(true);
    // Paged "Disable zoom in" drops the whole zoom wrapper (pinch AND the
    // double-tap-drag zoom).
    final isZoomDisabled = ref.watch(disableZoomInProvider).ifNull();
    // Double-tap-to-zoom + disable-zoom-out — consumed by ZoomView.
    final isDoubleTapZoomEnabled =
        ref.watch(doubleTapToZoomProvider).ifNull(true);
    final isZoomOutDisabled = ref.watch(disableZoomOutProvider).ifNull();
    // "Rotate wide pages to fit": per-image render transform, applied on next
    // reader open like the other toggles.
    final rotateWide = ref.read(rotateWidePagesProvider).ifNull();
    final rotateWideInvert = ref.read(rotateWideInvertProvider).ifNull();
    // Auto-crop solid borders — decoder-level via
    // ServerImage, so it composes with rotate/split/double.
    final cropBorders = ref.read(cropBordersProvider).ifNull();
    // Image scale type → the page's BoxFit + decode size.
    final scaleType =
        ref.read(imageScaleTypeKeyProvider) ?? ImageScaleType.fitScreen;
    final (pageFit, pageSize) =
        scaleType.pagedFit(context.width, context.height);
    // Intra-pair slot order: invertDoublePages, flipped again under RTL.
    final reversePair = invertDouble != reverse;
    final itemCount = composite
        ? (mapping!.isEmpty ? 1 : mapping.length)
        : (chapterPages.pages.isEmpty ? 1 : chapterPages.pages.length);
    return ReaderWrapper(
      scrollDirection: scrollDirection,
      chapter: chapter,
      manga: manga,
      chapterPages: chapterPages,
      currentIndex: currentIndex.value,
      // Seekbar addresses RAW pages → map to the display position.
      onChanged: (index) => scrollController
          .jumpToPage(mapping == null ? index : mapping.rawToDisplay(index)),
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      onPrevious: () => scrollController.previousPage(
        duration: pagedNavDuration(animate: isAnimationEnabled),
        curve: kCurve,
      ),
      onNext: () => scrollController.nextPage(
        duration: pagedNavDuration(animate: isAnimationEnabled),
        curve: kCurve,
      ),
      pageController: scrollController,
      child: AppUtils.wrapOn(
        !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !isZoomDisabled
            ? (Widget child) => ReaderZoomView(
                  controller: scrollController,
                  scrollAxis: scrollDirection,
                  maxScale: 5,
                  minScale: isZoomOutDisabled ? 1 : 0.5,
                  // Paged zoom is gated wholesale by "disable zoom in"; when the
                  // wrapper is present, pinch is available.
                  pinchEnabled: true,
                  doubleTapToZoom: isDoubleTapZoomEnabled,
                  child: child,
                )
            : null,
        PageView.builder(
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: scrollController,
          allowImplicitScrolling: true,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          itemBuilder: (BuildContext context, int index) {
            // Show loading indicator if no pages are available yet
            if (chapterPages.pages.isEmpty) {
              return const Center(
                child: CenterSorayomiShimmerIndicator(),
              );
            }

            // Composite path: render a spread / split half for this display
            // position. RAW-page reporting stays intact via [mapping].
            if (mapping != null) {
              if (index >= mapping.length) {
                return const Center(child: CenterSorayomiShimmerIndicator());
              }
              return DoublePageView(
                entry: mapping.entries[index],
                pages: chapterPages.pages,
                pageFit: pageFit,
                pageSize: pageSize,
                centerMargin: centerMargin,
                rotateWide: rotateWide,
                rotateWideInvert: rotateWideInvert,
                reversePair: reversePair,
                onPageWide: onPageWide,
                cropBorders: cropBorders,
              );
            }

            // Add bounds checking to prevent accessing non-existent pages
            if (index >= chapterPages.pages.length) {
              return const Center(
                child: CenterSorayomiShimmerIndicator(),
              );
            }

            return ServerImage(
              showReloadButton: true,
              fit: pageFit,
              size: pageSize,
              appendApiToUrl: false,
              cropBorders: cropBorders,
              imageUrl: chapterPages.pages[index],
              // Only set when rotating, so the default render path is
              // untouched while the toggle is off.
              imageBuilder: rotateWide
                  ? (context, imageProvider) => RotateWidePage(
                        imageProvider: imageProvider,
                        invert: rotateWideInvert,
                      )
                  : null,
              progressIndicatorBuilder: (context, url, downloadProgress) =>
                  CenterSorayomiShimmerIndicator(
                value: downloadProgress.progress,
              ),
            );
          },
          itemCount: itemCount,
        ),
      ),
    );
  }
}
