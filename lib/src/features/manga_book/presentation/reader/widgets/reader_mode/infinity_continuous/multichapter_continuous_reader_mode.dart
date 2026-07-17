// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../../../constants/db_keys.dart';
import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/app_utils.dart';
import '../../../../../../../widgets/server_image.dart';
import '../../../../../../../widgets/zoom/scroll_offset_to_scroll_controller.dart';
import '../../../../../../history/presentation/history_controller.dart';
import '../../../../../../offline/data/offline_download_providers.dart';
import '../../../../../../offline/data/offline_repository.dart';
import '../../../../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_scroll_animation_tile/reader_scroll_animation_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import '../../../../../../tracking/domain/track_progress_gate.dart';
import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../../domain/manga/manga_model.dart';
import '../../../../manga_details/controller/manga_details_controller.dart';
import '../../../controller/auto_scroll_controller.dart';
import '../../../controller/reader_controller.dart';
import '../../../utils/flush_progress_on_lifecycle.dart';
import '../../../utils/reader_initial_page.dart';
import '../../reader_wrapper.dart';
import '../reader_zoom_view.dart';
import 'infinity_continuous_config.dart';
import 'infinity_continuous_feedback.dart';
import 'infinity_continuous_utils.dart';
import 'measure_size.dart';

/// Pixels to advance this auto-scroll frame. [intervalSeconds] is the pace
/// setting (seconds to glide one full viewport); [dtMs] is elapsed time since
/// the previous tick.
double autoScrollDelta({
  required double viewport,
  required int intervalSeconds,
  required int dtMs,
}) {
  if (intervalSeconds <= 0) return 0;
  final pxPerMs = viewport / (intervalSeconds * 1000);
  return pxPerMs * dtMs;
}

typedef _LoadedChapter = ({
  ChapterPagesDto pages,
  ChapterDto chapter,
  int chapterId,
});

/// Multi-chapter webtoon reader built on ``ScrollablePositionedList``.
///
/// Replaces the homegrown plain-``ListView`` reader. SPL gives us reliable
/// index-based navigation and visible item reporting, but its underlying scroll
/// position is still pixel based: when an async image above the viewport changes
/// height, Flutter does not anchor the currently visible page for us. This
/// widget records rendered page heights and compensates above-viewport resize
/// deltas so the webtoon strip the user is reading stays visually pinned.
///
/// Multi-chapter handling:
///   * Forward (next chapter) is APPENDED — front indices are unchanged,
///     so SPL needs no re-anchor and the transition is seamless.
///   * Backward (previous chapter) is PREPENDED — every index shifts up
///     by the new chapter's page count, so right after the insert we
///     ``jumpTo`` the same content at its new index + alignment. The old
///     reader deferred this by two frames (postFrame + endOfFrame) which
///     showed one frame of wrong content; we re-anchor without the
///     double-defer.
class MultiChapterContinuousReaderMode extends HookConsumerWidget {
  const MultiChapterContinuousReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    this.onPageChanged,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.showReaderLayoutAnimation = false,
    this.effectiveReaderMode = ReaderMode.webtoon,
    this.openAtEnd = false,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final ValueSetter<int>? onPageChanged;
  final Axis scrollDirection;
  final bool reverse;
  final bool showReaderLayoutAnimation;
  final ReaderMode effectiveReaderMode;
  final bool openAtEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether the reader feedback snackbars are enabled (user setting). Read
    // live so toggling the setting applies without reopening the reader.
    bool readerToastsEnabled() =>
        ref.read(readerFeedbackToastsProvider).ifNull(true);
    final ItemScrollController itemScrollController =
        useMemoized(() => ItemScrollController());
    final ItemPositionsListener positionsListener =
        useMemoized(() => ItemPositionsListener.create());
    final ScrollOffsetController scrollOffsetController =
        useMemoized(() => ScrollOffsetController());
    final ScrollController zoomScrollController = useMemoized(
      () => ScrollOffsetToScrollController(
        scrollOffsetController: scrollOffsetController,
      ),
      [scrollOffsetController],
    );

    final loadedChapters = useState<List<_LoadedChapter>>([
      (pages: chapterPages, chapter: chapter, chapterId: chapter.id),
    ]);
    // Mirror of loadedChapters so the (once-bound) position listener
    // always reads the latest list without rebinding on every change.
    final loadedRef = useRef<List<_LoadedChapter>>(loadedChapters.value);
    loadedRef.value = loadedChapters.value;

    // Per-page measured rendered height, keyed by image URL. Page images load
    // with no intrinsic height, so a page that gets disposed on a long scroll
    // re-enters as a tiny placeholder and then grows on decode — which yanks
    // the scroll backward to the top of the previous strip. Recording each
    // page's true height the first time it lays out lets us reserve that exact
    // height in the placeholder on re-entry, so the strip never collapses and
    // the scroll stays put. Reader-scoped so it survives item dispose/rebuild.
    final pageHeights = useRef<Map<String, double>>(<String, double>{});
    // Bumped each time a new ordered prefetch sweep starts, so a stale sweep
    // (from before a seek / chapter load) cancels itself.
    final prefetchGen = useRef<int>(0);
    // True while a programmatic jump (seek / prepend re-anchor) is still
    // settling. The position listener otherwise reads its transient positions
    // as a user scroll and can auto-load a neighbour chapter mid-seek — which
    // shifts every index and bounces the landing (the single-tap seek bug).
    // The isAdjustingScroll flag below (+ adjustIdleTimer) is that guard.
    final isAdjustingScroll = useRef<bool>(false);
    final adjustIdleTimer = useRef<Timer?>(null);

    final currentVisibleChapter = useState<ChapterDto>(chapter);
    final initialChapterPageIndex = readerInitialPageIndex(
      chapter: chapter,
      chapterPages: chapterPages,
      openAtEnd: openAtEnd,
    );
    final currentChapterPageIndex = useState<int>(initialChapterPageIndex);

    final loadingNext = useState(false);
    final loadingPrevious = useState(false);
    final hasReachedEnd = useState(false);
    final hasReachedStart = useState(false);

    final lastEndFeedbackTime = useRef<DateTime?>(null);
    final lastStartFeedbackTime = useRef<DateTime?>(null);
    final completedChapterIds = useRef<Set<int>>({});
    final lastVisibleChapterId = useRef<int>(chapter.id);
    // Top-most visible (index, leadingEdge) from the previous listener
    // tick, used to derive scroll direction so neighbour chapters load
    // only when the user scrolls TOWARD an edge — never on initial open.
    final lastTop = useRef<({int index, double edge})?>(null);

    // WATCH, not a one-time read: on a cold open the filtered chapter list is
    // still loading, so a read-once here pinned both neighbours to null for
    // the whole session (no next/previous chapter ever loaded). Mirrored into
    // a ref so the once-bound scroll listener below reads the live value.
    final nextPrevChapterPair =
        useRef<({ChapterDto? first, ChapterDto? second})?>(null);
    nextPrevChapterPair.value = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: currentVisibleChapter.value.id,
      ),
    );

    // --- reading-progress recording -------------------------------------
    // Record progress for the CURRENTLY VISIBLE chapter, not the chapter the
    // reader was opened with. In a multi-chapter session the visible chapter
    // changes as you scroll across boundaries; the old code forwarded a
    // visible-chapter-relative page index up to ReaderScreen, which wrote it to
    // the OPENED chapter's id — corrupting that chapter's resume state and
    // losing the visible chapter's. We also go through the offline-safe
    // recordReadingProgress path so a read made offline is queued, not lost.
    final progressDebounce = useRef<Timer?>(null);
    final latestProgress = useRef<({int chapterId, int rel})?>(null);

    _LoadedChapter? loadedById(int id) {
      for (final c in loadedRef.value) {
        if (c.chapterId == id) return c;
      }
      return null;
    }

    Future<void> writeVisibleProgress(int chapterId, int rel) async {
      // Debounce can fire after the reader's gone.
      if (!context.mounted) return;
      if (ref.read(incognitoModeProvider)) return;
      // We've already moved past this chapter — a late debounced partial must
      // not revert what the boundary mark-read recorded for it. Let that path
      // own the chapter's final state.
      if (chapterId != currentVisibleChapter.value.id) return;
      // Already finished this session (by us or the boundary handler): don't
      // re-record or re-fire side effects.
      if (completedChapterIds.value.contains(chapterId)) return;
      final lc = loadedById(chapterId);
      if (lc == null) return;
      // Already read in a prior session: leave it alone (mirrors the single-page
      // reader, which skips progress writes for read chapters).
      if (lc.chapter.isRead.ifNull()) return;
      final pageCount = lc.pages.pages.length;
      final completed = rel >= (pageCount - 1) && pageCount > 0;
      // Don't write a lower page than what's already saved (at-open snapshot),
      // unless we're completing the chapter.
      if (!completed &&
          lc.chapter.lastPageRead.getValueOnNullOrNegative() >= rel) {
        return;
      }
      await recordReadingProgress(
        ref,
        chapterId: chapterId,
        lastPageRead: completed ? 0 : rel,
        isRead: completed,
      );
      // Disposed during the await → the ref calls below would throw.
      if (!context.mounted) return;
      if (completed && !completedChapterIds.value.contains(chapterId)) {
        completedChapterIds.value = {...completedChapterIds.value, chapterId};
        unawaited(maybeTrackProgressOnReadFetch(ref,
            mangaId: manga.id, isRead: true, manual: false));
        unawaited(maybeDeleteOnReadLocal(ref,
            mangaId: manga.id, readChapterId: chapterId));
        unawaited(maybeDeleteOnReadServer(ref,
            mangaId: manga.id, readChapterId: chapterId));
      }
      ref.invalidate(readingHistoryProvider);
    }

    void scheduleVisibleProgress(int chapterId, int rel) {
      if (ref.read(incognitoModeProvider)) return;
      latestProgress.value = (chapterId: chapterId, rel: rel);
      progressDebounce.value?.cancel();
      final pageCount = loadedById(chapterId)?.pages.pages.length ?? 0;
      if (rel >= (pageCount - 1) && pageCount > 0) {
        // Completion: write immediately so finishing a chapter isn't lost to a
        // pending debounce.
        unawaited(writeVisibleProgress(chapterId, rel));
      } else {
        progressDebounce.value = Timer(
          const Duration(seconds: 2),
          () => unawaited(writeVisibleProgress(chapterId, rel)),
        );
      }
    }

    useEffect(() {
      scheduleVisibleProgress(
          currentVisibleChapter.value.id, currentChapterPageIndex.value);
      return null;
    }, [currentChapterPageIndex.value, currentVisibleChapter.value.id]);

    // Flush any pending debounced progress when the reader is torn down, so
    // exiting mid-chapter still saves the visible chapter's position. The db +
    // flags are captured at build so the teardown never touches `ref` after the
    // element starts disposing; the write goes straight to the on-device
    // catalog (left dirty, so it up-syncs on reconnect) instead of the
    // ref-dependent recordReadingProgress path.
    final offlineEnabledForFlush = ref.read(offlineEnabledProvider);
    final offlineDbForFlush =
        offlineEnabledForFlush ? ref.read(offlineDatabaseProvider) : null;
    final incognitoForFlush = ref.read(incognitoModeProvider);
    useEffect(() {
      return () {
        progressDebounce.value?.cancel();
        final p = latestProgress.value;
        if (p == null) return;
        // Already finished (an earlier in-session completion): nothing to flush.
        if (completedChapterIds.value.contains(p.chapterId)) return;
        if (incognitoForFlush || offlineDbForFlush == null) return;
        // If the pending position is itself a completion (last page), write
        // isRead:true — so a teardown that races the still-in-flight completion
        // write (which may not have updated completedChapterIds yet) records the
        // read instead of reverting it to unread. Otherwise save the partial.
        final lc = loadedById(p.chapterId);
        final pageCount = lc?.pages.pages.length ?? 0;
        final isCompletion = pageCount > 0 && p.rel >= pageCount - 1;
        unawaited(offlineDbForFlush
            .setChapterProgress(p.chapterId,
                lastPageRead: isCompletion ? 0 : p.rel,
                // Never un-read on a teardown flush: only a completion marks read.
                isRead: isCompletion ? true : null)
            .catchError((_) {}));
      };
    }, const []);

    // Desktop window-close fires neither a route-pop nor a reliable dispose,
    // and the teardown flush above is offline-only; flush the visible position
    // to the server on background/exit too.
    useFlushProgressOnAppLifecycle(() async {
      progressDebounce.value?.cancel();
      final p = latestProgress.value;
      if (p == null) return;
      if (completedChapterIds.value.contains(p.chapterId)) return;
      await writeVisibleProgress(p.chapterId, p.rel);
    });

    final bool isAnimationEnabled =
        ref.watch(readerScrollAnimationProvider).ifNull(true);
    final bool isPinchToZoomEnabled =
        ref.watch(pinchToZoomProvider).ifNull(true);
    final bool isDoubleTapZoomEnabled =
        ref.watch(doubleTapToZoomProvider).ifNull(true);
    final bool isZoomOutDisabled = ref.watch(disableZoomOutProvider).ifNull();
    // Auto-crop borders. Render-only: the crop
    // provider's async decode is handled by the imageBuilder's frameBuilder
    // below, which still reserves placeholderHeight and measures the cropped
    // strip — the scroll/height math is untouched.
    final bool cropBorders = ref.watch(cropBordersWebtoonProvider).ifNull();
    final ReaderScrollAmount scrollAmount =
        ref.watch(readerScrollAmountKeyProvider) ??
            DBKeys.readerScrollAmount.initial as ReaderScrollAmount;

    final bool autoScrollActive = ref.watch(autoScrollActiveProvider);
    final bool smoothAutoScroll = ref.watch(smoothAutoScrollProvider) ??
        DBKeys.smoothAutoScroll.initial as bool;
    final int autoScrollIntervalSeconds =
        ref.watch(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
    // Set around every auto-scroll-driven jump so the manual-scroll listener
    // (below) doesn't mistake the engine's own motion for the user grabbing
    // the strip and stop itself.
    final programmaticScroll = useRef<bool>(false);
    final lastAutoScrollTick = useRef<Duration>(Duration.zero);

    // Decode a page's image off-screen AND record its true rendered height from
    // the decoded aspect ratio. Caching the height
    // is the load-bearing part: a page then ALWAYS lays out at its real height —
    // even before its widget is built, and even if its bitmap was later evicted
    // — so it never resizes on landing/scroll-in and never shoves the viewport.
    Future<void> decodeAndCacheHeight(String url) async {
      if (pageHeights.value.containsKey(url)) return;
      final provider = serverPageImageProvider(ref, url);
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ImageInfo>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (!completer.isCompleted) completer.complete(info);
        stream.removeListener(listener);
      }, onError: (e, st) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      final info = await completer.future;
      final w = info.image.width;
      final h = info.image.height;
      if (w > 0 && h > 0 && context.mounted) {
        // Rendered height for a fitWidth strip spanning the viewport width.
        pageHeights.value[url] = MediaQuery.sizeOf(context).width * h / w;
      }
      info.dispose();
    }

    // Decode pages ONCE, off-screen and ahead of the viewport, in reading order
    // — so a page is already decoded AND its height is known before it's
    // reached/jumped-to; nothing resizes on/above screen. A generation token
    // cancels an in-flight sweep when a new one starts (seek / chapter load).
    void prefetchPagesFrom(int startGlobalIndex) {
      final gen = ++prefetchGen.value;
      Future(() async {
        final urls = <String>[
          for (final c in loadedRef.value) ...c.pages.pages,
        ];
        if (urls.isEmpty) return;
        final start = startGlobalIndex.clamp(0, urls.length - 1);
        final order = <int>[
          for (var i = start; i < urls.length; i++) i,
          for (var i = start - 1; i >= 0; i--) i,
        ];
        for (final i in order) {
          if (!context.mounted || prefetchGen.value != gen) return;
          try {
            await decodeAndCacheHeight(urls[i]);
          } catch (_) {}
        }
      });
    }

    // Global (across all loaded chapters) index of the page being read now.
    int currentGlobalIndex() {
      var cumulative = 0;
      for (final c in loadedRef.value) {
        if (c.chapterId == currentVisibleChapter.value.id) {
          return cumulative + currentChapterPageIndex.value;
        }
        cumulative += c.pages.pages.length;
      }
      return currentChapterPageIndex.value;
    }

    // Start the ordered prefetch once, after the first layout.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) prefetchPagesFrom(currentChapterPageIndex.value);
      });
      return () => adjustIdleTimer.value?.cancel();
    }, const []);

    // Open a short window during which the position listener won't auto-load a
    // neighbour chapter. Called around programmatic jumps so their settle
    // motion isn't mistaken for the user scrolling toward an edge.
    void markScrollAdjusting() {
      isAdjustingScroll.value = true;
      adjustIdleTimer.value?.cancel();
      adjustIdleTimer.value = Timer(
        const Duration(milliseconds: 350),
        () => isAdjustingScroll.value = false,
      );
    }

    void jumpToIndex({required int index, double alignment = 0}) {
      if (!itemScrollController.isAttached) return;
      itemScrollController.jumpTo(index: index, alignment: alignment);
      // Re-seed the decode order from the new position so the pages we just
      // jumped onto (and the ones ahead) are decoded before they're scrolled
      // past — otherwise a far jump lands on undecoded strips that resize.
      prefetchPagesFrom(index);
    }

    // --- chapter loading -------------------------------------------------

    Future<void> loadNextChapter(ChapterDto next) async {
      if (loadingNext.value || hasReachedEnd.value) return;
      if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
      loadingNext.value = true;
      try {
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showLoadingNextChapterFeedback(
              context, next.name);
        }
        // Timeout so a hung fetch (Riverpod 3 retries a failing provider
        // while .future waits) releases the loading guard; a failed or null
        // fetch stays retryable on the next edge gesture instead of latching
        // "end reached" for the whole session.
        final pages = await ref
            .read(chapterPagesProvider(chapterId: next.id).future)
            .timeout(const Duration(seconds: 15));
        if (pages == null) {
          // Drop the cached null so the next gesture refetches.
          ref.invalidate(chapterPagesProvider(chapterId: next.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
        loadedChapters.value = [
          ...loadedChapters.value,
          (pages: pages, chapter: next, chapterId: next.id),
        ];
        // Decode the appended chapter's pages ahead of the user reaching them.
        prefetchPagesFrom(currentGlobalIndex());
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showNextChapterLoadedFeedback(
              context, next.name);
        }
      } catch (_) {
        // Transient failure — leave unlatched and refetchable so the next
        // gesture retries.
        ref.invalidate(chapterPagesProvider(chapterId: next.id));
      } finally {
        loadingNext.value = false;
      }
    }

    Future<void> loadPreviousChapter(ChapterDto prev) async {
      if (loadingPrevious.value || hasReachedStart.value) return;
      if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;
      loadingPrevious.value = true;
      try {
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showLoadingPreviousChapterFeedback(
              context, prev.name);
        }
        // Same timeout/no-latch/refetch treatment as loadNextChapter above.
        final pages = await ref
            .read(chapterPagesProvider(chapterId: prev.id).future)
            .timeout(const Duration(seconds: 15));
        if (pages == null) {
          ref.invalidate(chapterPagesProvider(chapterId: prev.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;

        final newPageCount = pages.pages.length;

        // Capture the page currently anchoring the viewport so we can
        // re-pin it after every index shifts up by ``newPageCount``.
        final positions = positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
        int? anchorIndex;
        double anchorAlignment = 0.0;
        for (final p in positions) {
          // First item whose top edge is at/below the viewport top is the
          // natural anchor; fall back to the first reported position.
          if (p.itemTrailingEdge > 0) {
            anchorIndex = p.index;
            anchorAlignment = p.itemLeadingEdge.clamp(-1.0, 1.0);
            break;
          }
        }
        anchorIndex ??= positions.isNotEmpty ? positions.first.index : null;

        loadedChapters.value = [
          (pages: pages, chapter: prev, chapterId: prev.id),
          ...loadedChapters.value,
        ];
        // Indices just shifted up by newPageCount; drop the stale
        // direction sample so the next tick re-derives it cleanly.
        lastTop.value = null;

        // Re-anchor on the next frame (the rebuilt SPL must register the
        // new itemCount first). One frame, no animation, no second defer.
        if (anchorIndex != null) {
          final target = anchorIndex + newPageCount;
          // Guard the re-anchor jump too: its settle motion must not be read
          // as a scroll back to the top that prepends yet another chapter.
          markScrollAdjusting();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            jumpToIndex(index: target, alignment: anchorAlignment);
          });
        }

        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
              context, prev.name);
        }
      } catch (_) {
        // Transient failure — leave unlatched and refetchable so the next
        // gesture retries.
        ref.invalidate(chapterPagesProvider(chapterId: prev.id));
      } finally {
        loadingPrevious.value = false;
      }
    }

    // --- position tracking ----------------------------------------------

    useEffect(() {
      void listener() {
        final loaded = loadedRef.value;
        final total = InfinityContinuousUtils.getTotalPages(loaded);
        if (total <= 0) return;

        final positions = positionsListener.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList();
        if (positions.isEmpty) return;

        // Most-visible page → current global index (last page wins once its
        // bottom reaches the viewport, so short trailing pages still complete).
        final globalIdx = InfinityContinuousUtils.selectCurrentIndex(
          positions,
          total,
          minVisibleAreaThreshold:
              InfinityContinuousConfig.minVisibleAreaThreshold,
        );
        if (globalIdx == null) return;

        // Map the global index to (chapter, page-within-chapter).
        int cumulative = 0;
        for (final ch in loaded) {
          final count = ch.pages.pages.length;
          if (globalIdx >= cumulative && globalIdx < cumulative + count) {
            final rel = globalIdx - cumulative;
            if (currentChapterPageIndex.value != rel) {
              currentChapterPageIndex.value = rel;
            }
            if (currentVisibleChapter.value.id != ch.chapter.id) {
              final prevId = lastVisibleChapterId.value;
              final prevPos = loaded.indexWhere((e) => e.chapterId == prevId);
              final newPos =
                  loaded.indexWhere((e) => e.chapterId == ch.chapter.id);
              currentVisibleChapter.value = ch.chapter;
              lastVisibleChapterId.value = ch.chapter.id;
              // Forward boundary crossing: the chapter we just left is
              // finished → mark it read.
              if (prevPos >= 0 && newPos > prevPos) {
                final left = loaded[prevPos].chapter;
                _markChapterRead(
                    ref, manga.id, left, completedChapterIds, context);
              }
            }
            break;
          }
          cumulative += count;
        }

        // A programmatic jump (seek / prepend re-anchor) is still settling —
        // its transient positions must not look like the user scrolling to an
        // edge, or we'd auto-load a neighbour chapter and shift the indices
        // out from under the jump. Skip edge handling until it settles, and
        // drop the stale direction sample so the first real tick starts clean.
        if (isAdjustingScroll.value) {
          lastTop.value = null;
          return;
        }

        // Boundary prefetch triggers — gated on scroll DIRECTION so that
        // opening a chapter (at page 0, or a short chapter) never auto-
        // loads a neighbour. A neighbour loads only when the user is
        // actively scrolling toward that edge.
        final minIdx =
            positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
        final maxIdx =
            positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

        final top = positions.reduce((a, b) => a.index <= b.index ? a : b);
        final prevTop = lastTop.value;
        lastTop.value = (index: top.index, edge: top.itemLeadingEdge);
        bool scrollingUp = false;
        bool scrollingDown = false;
        if (prevTop != null) {
          const eps = 0.0015;
          if (top.index < prevTop.index) {
            scrollingUp = true;
          } else if (top.index > prevTop.index) {
            scrollingDown = true;
          } else if (top.itemLeadingEdge > prevTop.edge + eps) {
            // top page slid down the screen → content moved down → up-scroll
            scrollingUp = true;
          } else if (top.itemLeadingEdge < prevTop.edge - eps) {
            scrollingDown = true;
          }
        }

        if (scrollingDown && maxIdx >= total - 2) {
          final pair = nextPrevChapterPair.value;
          final next = pair?.first;
          if (next != null) {
            loadNextChapter(next);
          } else if (pair != null && !hasReachedEnd.value) {
            // The list resolved and there is genuinely no next chapter — the
            // only state that may latch the end (a null pair just means the
            // chapter list hasn't loaded yet).
            hasReachedEnd.value = true;
            // Only surface the end-of-manga toast once the bottom of the very
            // last page is actually on screen. On long webtoon pages the last
            // page item becomes "visible" (counts toward maxIdx) long before
            // the reader reaches its end, which previously spammed the toast on
            // every scroll. itemTrailingEdge <= 1.0 means the page bottom has
            // reached (or passed) the viewport bottom.
            final lastPage = positions.where((p) => p.index == total - 1);
            final atBottom =
                lastPage.isNotEmpty && lastPage.first.itemTrailingEdge <= 1.0;
            if (atBottom && readerToastsEnabled()) {
              InfinityContinuousFeedback.showEndOfMangaFeedback(
                  context, lastEndFeedbackTime);
            }
          }
        }
        if (scrollingUp && minIdx <= 0) {
          final pair = nextPrevChapterPair.value;
          final prev = pair?.second;
          if (prev != null) {
            loadPreviousChapter(prev);
          } else if (pair != null && !hasReachedStart.value) {
            hasReachedStart.value = true;
            if (readerToastsEnabled()) {
              InfinityContinuousFeedback.showStartOfMangaFeedback(
                  context, lastStartFeedbackTime);
            }
          }
        }
      }

      positionsListener.itemPositions.addListener(listener);
      return () => positionsListener.itemPositions.removeListener(listener);
      // Bind once; the listener reads loadedRef for the live chapter list.
    }, const []);

    // --- navigation ------------------------------------------------------

    void jumpToChapterRelative(int chapterIdx) {
      final globalIndex =
          InfinityContinuousUtils.convertChapterIndexToGlobalIndex(
        chapterIdx,
        loadedChapters.value,
        currentVisibleChapter.value.id,
      );
      if (globalIndex < 0) return;
      if (!itemScrollController.isAttached) return;
      currentChapterPageIndex.value = chapterIdx;
      // Jump IMMEDIATELY — itemScrollController.jumpTo(index:), no await, so the
      // landing is instant instead of deferred. The old
      // path awaited ~10 sequential off-screen image decodes BEFORE jumping —
      // a multi-second window (2.4s on-device, worse under download load) in
      // which the position listener auto-loaded a neighbour chapter and shifted
      // every index out from under the pending jump, so a single tap landed in
      // the wrong chapter and bounced. Page heights are already estimated from
      // measured siblings, so the landing is stable without pre-decoding.
      markScrollAdjusting();
      lastTop.value = null;
      itemScrollController.jumpTo(index: globalIndex, alignment: 0);
      // Decode forward from the new position in the background so the pages the
      // user is about to scroll into are ready.
      prefetchPagesFrom(globalIndex);
    }

    void handlePageNavigation({required bool isNext}) {
      final globalIndex =
          InfinityContinuousUtils.convertChapterIndexToGlobalIndex(
        currentChapterPageIndex.value + (isNext ? 1 : -1),
        loadedChapters.value,
        currentVisibleChapter.value.id,
      );
      if (globalIndex < 0) return;
      if (!itemScrollController.isAttached) return;
      if (isAnimationEnabled) {
        itemScrollController.scrollTo(
          index: globalIndex,
          alignment: 0.0,
          duration: InfinityContinuousConfig.scrollAnimationDuration,
          curve: InfinityContinuousConfig.scrollAnimationCurve,
        );
      } else {
        jumpToIndex(index: globalIndex);
      }
    }

    void handleViewportScroll({required bool forward}) {
      if (!itemScrollController.isAttached) return;
      try {
        final ScrollPosition pos = scrollOffsetController.position;
        final double viewport = pos.viewportDimension;
        // reverse:true flips the visual direction of the list.
        final double sign = (forward ? 1.0 : -1.0) * (reverse ? -1.0 : 1.0);
        scrollOffsetController.animateScroll(
          offset: viewport * scrollAmount.fraction * sign,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // Attached but not laid out yet (no ScrollPosition) — skip this press.
      }
    }

    // --- auto-scroll engine -----------------------------------------------
    //
    // Smooth mode drives per-frame pixel deltas straight on the
    // ScrollPosition; jump mode reuses handlePageNavigation on a periodic
    // timer (Komikku's scrollDown() analog). Both stop themselves at the end
    // of the last loaded chapter, and are stopped externally by the manual-
    // scroll listener and the app-lifecycle listener below.

    bool atLastLoadedPage() =>
        hasReachedEnd.value &&
        currentGlobalIndex() >=
            InfinityContinuousUtils.getTotalPages(loadedChapters.value) - 1;

    void onAutoScrollTick(Duration elapsed) {
      if (!itemScrollController.isAttached) return;
      final dtMs = (elapsed - lastAutoScrollTick.value).inMilliseconds;
      lastAutoScrollTick.value = elapsed;
      if (dtMs <= 0) return;
      try {
        final pos = scrollOffsetController.position;
        final interval = ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        final delta = autoScrollDelta(
          viewport: pos.viewportDimension,
          intervalSeconds: interval,
          dtMs: dtMs,
        );
        final target = pos.pixels + (reverse ? -delta : delta);
        if (target >= pos.maxScrollExtent && hasReachedEnd.value) {
          ref.read(autoScrollActiveProvider.notifier).stop();
          return;
        }
        programmaticScroll.value = true;
        pos.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
        programmaticScroll.value = false;
      } catch (_) {
        // Attached but not laid out yet (no ScrollPosition) — skip this tick.
      }
    }

    // useSingleTickerProvider's TickerProvider only permits ONE createTicker
    // call per hook instance (a second call asserts) — so the Ticker itself
    // is built exactly once via useMemoized and then just started/stopped as
    // the active/smooth state changes, never recreated.
    final autoScrollTickerProvider = useSingleTickerProvider();
    final autoScrollTicker = useMemoized(
      () => autoScrollTickerProvider.createTicker(onAutoScrollTick),
      const [],
    );

    useEffect(() {
      if (autoScrollActive && smoothAutoScroll) {
        lastAutoScrollTick.value = Duration.zero;
        if (!autoScrollTicker.isActive) autoScrollTicker.start();
      } else if (autoScrollTicker.isActive) {
        autoScrollTicker.stop();
      }
      return null;
    }, [autoScrollActive, smoothAutoScroll]);

    // Jump mode (smoothAutoScroll off): periodic page-advance instead of a
    // per-frame glide.
    useEffect(() {
      Timer? timer;
      if (autoScrollActive && !smoothAutoScroll) {
        timer = Timer.periodic(
          Duration(seconds: autoScrollIntervalSeconds),
          (_) {
            if (atLastLoadedPage()) {
              ref.read(autoScrollActiveProvider.notifier).stop();
              return;
            }
            programmaticScroll.value = true;
            handlePageNavigation(isNext: true);
            programmaticScroll.value = false;
          },
        );
      }
      return () => timer?.cancel();
    }, [autoScrollActive, smoothAutoScroll, autoScrollIntervalSeconds]);

    // The ticker outlives both effects above (it's created once); stop and
    // dispose it only on the widget's own teardown.
    useEffect(() {
      return () {
        if (autoScrollTicker.isActive) autoScrollTicker.stop();
        autoScrollTicker.dispose();
      };
    }, const []);

    // Backgrounding the app mid-glide would otherwise leave auto-scroll
    // running (and writing progress) while the user isn't looking.
    useEffect(() {
      final listener = AppLifecycleListener(
        onHide: () => ref.read(autoScrollActiveProvider.notifier).stop(),
        onPause: () => ref.read(autoScrollActiveProvider.notifier).stop(),
      );
      return listener.dispose;
    }, const []);

    // --- build -----------------------------------------------------------

    final total = InfinityContinuousUtils.getTotalPages(loadedChapters.value);

    Widget buildItem(BuildContext context, int index) {
      final loc = _locate(index, loadedChapters.value);
      if (loc == null) {
        return SizedBox(
          height:
              context.height * InfinityContinuousConfig.verticalPageHeightRatio,
        );
      }
      // Reserve the page's true height so a strip never grows on decode and
      // shoves the scroll backward. Priority:
      //   1. this exact page's measured height (re-entry), else
      //   2. the AVERAGE of pages already measured in this session — manhwa
      //      strips in a chapter are near-uniform, so this places an unloaded
      //      page within a few px of its real height (the key fix: a page that
      //      loads while ABOVE the viewport barely changes size, so it doesn't
      //      push the reader back — the failure mode the 0.7-screen guess caused
      //      when real strips are 2-4 screens tall), else
      //   3. a one-screen fallback for the very first page (the anchor, which
      //      grows downward and never jumps the reader).
      final measured = pageHeights.value;
      final double? avgHeight = measured.isEmpty
          ? null
          : measured.values.reduce((a, b) => a + b) / measured.length;
      final placeholderHeight = measured[loc.imageUrl] ??
          avgHeight ??
          context.height * InfinityContinuousConfig.verticalPageHeightRatio;
      return ServerImage(
        showReloadButton: true,
        fit: BoxFit.fitWidth,
        appendApiToUrl: false,
        cropBorders: cropBorders,
        // Decode at on-screen width, not the ~800×15000 source (#196 GPU cost).
        memCacheWidth: (context.width * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(1, 1 << 20),
        imageUrl: loc.imageUrl,
        progressIndicatorBuilder: (_, __, progress) => SizedBox(
          height: placeholderHeight,
          child: Center(
            child: CircularProgressIndicator(value: progress.progress),
          ),
        ),
        imageBuilder: (context, imageProvider) => Image(
          image: imageProvider,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          // A page file deleted while still loaded (e.g. delete-on-read, then
          // scrolling back to it offline) would otherwise throw and paint
          // Flutter's red error widget for every page. Show a stable-height
          // broken-image placeholder instead.
          errorBuilder: (context, error, stackTrace) => SizedBox(
            height: placeholderHeight,
            width: double.infinity,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.grey),
            ),
          ),
          // Reserve the page's height UNTIL the bitmap decodes. The network path
          // gets this for free via progressIndicatorBuilder, but the offline
          // (file://) ServerImage branch skips that and renders the bare Image —
          // which is 0px tall until the local file decodes, then pops to full
          // height. A wall of pages popping 0->real around a seek lands the jump
          // on the wrong page (offline-only seek bug). Reserving placeholderHeight
          // keeps every page size-stable, so jumpTo(index) lands true.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame == null && !wasSynchronouslyLoaded) {
              return SizedBox(
                  height: placeholderHeight, width: double.infinity);
            }
            // Only measure the REAL decoded image — never the placeholder — so a
            // strip re-entering the viewport reserves its true height.
            return MeasureSize(
              onChange: (size) {
                if (size.height <= 0) return;
                pageHeights.value[loc.imageUrl] = size.height;
              },
              child: child,
            );
          },
        ),
      );
    }

    Widget buildSeparator(BuildContext context, int index) {
      if (loadedChapters.value.length <= 1) return const SizedBox.shrink();
      if (!InfinityContinuousUtils.isChapterBoundary(
          index, loadedChapters.value)) {
        return const SizedBox.shrink();
      }
      final info = InfinityContinuousChapterSeparator.getSeparatorInfo(
          index, loadedChapters.value);
      if (info == null) return const SizedBox.shrink();
      return InfinityContinuousChapterSeparator(
        chapterName: info.chapterName,
        isChapterStart: info.isChapterStart,
      );
    }

    final positionedList = ScrollablePositionedList.separated(
      itemScrollController: itemScrollController,
      itemPositionsListener: positionsListener,
      scrollOffsetController: scrollOffsetController,
      initialScrollIndex: initialChapterPageIndex,
      scrollDirection: scrollDirection,
      reverse: reverse,
      itemCount: total,
      minCacheExtent:
          context.height * InfinityContinuousConfig.verticalCacheMultiplier,
      itemBuilder: buildItem,
      separatorBuilder: buildSeparator,
    );

    // A real user drag/fling stops auto-scroll immediately; the engine's own
    // jumps are excluded via the programmaticScroll guard set around them.
    final autoScrollAwareList = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (!programmaticScroll.value &&
            notification.direction != ScrollDirection.idle &&
            ref.read(autoScrollActiveProvider)) {
          ref.read(autoScrollActiveProvider.notifier).stop();
        }
        return false;
      },
      child: positionedList,
    );

    // Pinned at the scroll clamp a drag moves nothing, so the position
    // listener above never ticks and the direction-gated boundary triggers
    // can never fire — a resume landing on page 0 was an upward dead-end.
    // Clamping physics still reports every blocked drag as overscroll, so
    // treat edge overscroll as the boundary gesture.
    final edgeAwareList = NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (isAdjustingScroll.value || programmaticScroll.value) return false;
        final positions = positionsListener.itemPositions.value;
        if (positions.isEmpty) return false;
        var minIdx = positions.first.index;
        var maxIdx = positions.first.index;
        for (final p in positions) {
          if (p.index < minIdx) minIdx = p.index;
          if (p.index > maxIdx) maxIdx = p.index;
        }
        if (n.overscroll < 0 && minIdx <= 0) {
          final prev = nextPrevChapterPair.value?.second;
          if (prev != null) loadPreviousChapter(prev);
        } else if (n.overscroll > 0 &&
            maxIdx >=
                InfinityContinuousUtils.getTotalPages(loadedRef.value) - 1) {
          final next = nextPrevChapterPair.value?.first;
          if (next != null) loadNextChapter(next);
        }
        return false;
      },
      child: autoScrollAwareList,
    );

    final child = AppUtils.wrapOn(
      !kIsWeb &&
              (Platform.isAndroid || Platform.isIOS) &&
              (isPinchToZoomEnabled || isDoubleTapZoomEnabled)
          ? (Widget child) => ReaderZoomView(
                controller: zoomScrollController,
                scrollAxis: scrollDirection,
                maxScale: InfinityContinuousConfig.maxZoomScale,
                // Webtoon min zoom-out rate is 0.5 unless disabled.
                minScale: isZoomOutDisabled ? 1 : 0.5,
                pinchEnabled: isPinchToZoomEnabled,
                doubleTapToZoom: isDoubleTapZoomEnabled,
                child: child,
              )
          : null,
      edgeAwareList,
    );

    return ReaderWrapper(
      scrollDirection: scrollDirection,
      chapterPages: InfinityContinuousUtils.createChapterPagesDto(
          loadedChapters.value, currentVisibleChapter.value, chapterPages),
      chapter: currentVisibleChapter.value,
      manga: manga,
      showReaderLayoutAnimation: showReaderLayoutAnimation,
      currentIndex: currentChapterPageIndex.value,
      effectiveReaderMode: effectiveReaderMode,
      onChanged: jumpToChapterRelative,
      onPrevious: () => handlePageNavigation(isNext: false),
      onNext: () => handlePageNavigation(isNext: true),
      onViewportScrollForward: () => handleViewportScroll(forward: true),
      onViewportScrollBackward: () => handleViewportScroll(forward: false),
      // Reuse the slider-jump primitive (chapter-relative index -> global) so
      // currentChapterPageIndex/prefetch/scroll-adjust guard stay in sync,
      // rather than calling itemScrollController.jumpTo directly.
      onJumpToFirst: () => jumpToChapterRelative(0),
      onJumpToLast: () => jumpToChapterRelative(
          (loadedById(currentVisibleChapter.value.id)?.pages.pages.length ??
                  chapterPages.pages.length) -
              1),
      onToggleAutoScroll: () =>
          ref.read(autoScrollActiveProvider.notifier).toggle(),
      onAutoScrollFaster: () {
        final cur = ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        ref
            .read(autoScrollIntervalSecondsProvider.notifier)
            .update((cur - 1).clamp(1, 30));
      },
      onAutoScrollSlower: () {
        final cur = ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        ref
            .read(autoScrollIntervalSecondsProvider.notifier)
            .update((cur + 1).clamp(1, 30));
      },
      child: child,
    );
  }
}

/// Mark [chapter] read once and reconcile the relevant providers. Tracks
/// already-marked ids in [completedChapterIds] so repeated boundary
/// crossings don't re-fire the mutation.
void _markChapterRead(
  WidgetRef ref,
  int mangaId,
  ChapterDto chapter,
  ObjectRef<Set<int>> completedChapterIds,
  BuildContext context,
) {
  // Incognito: don't mark chapters read or fire history/tracker/delete on a
  // boundary crossing — leave no trace (parity with ReaderScreen's writes).
  if (ref.read(incognitoModeProvider)) return;
  if (chapter.isRead.ifNull()) return;
  if (completedChapterIds.value.contains(chapter.id)) return;
  completedChapterIds.value = {...completedChapterIds.value, chapter.id};
  // Record through the offline-safe path: persists to the on-device catalog
  // first (survives offline + restart), then pushes to the server and up-syncs
  // on reconnect. Previously this used a raw putChapter mutation, so a chapter
  // finished at a boundary while offline was never queued and the read was
  // silently lost.
  unawaited(recordReadingProgress(
    ref,
    chapterId: chapter.id,
    lastPageRead: 0,
    isRead: true,
  ).then((_) {
    if (!context.mounted) return;
    // Push progress to external trackers (fire-and-forget).
    unawaited(maybeTrackProgressOnReadFetch(
      ref,
      mangaId: mangaId,
      isRead: true,
      manual: false,
    ));
    // The chapter just crossed is behind the reader now → auto-delete it (both
    // the on-device copy and, per the server settings, the server copy). Each
    // no-ops if its own setting is off.
    unawaited(maybeDeleteOnReadLocal(
      ref,
      mangaId: mangaId,
      readChapterId: chapter.id,
    ));
    unawaited(maybeDeleteOnReadServer(
      ref,
      mangaId: mangaId,
      readChapterId: chapter.id,
    ));
  }));
  // NOTE: deliberately do NOT invalidate chapterProvider / mangaChapterList
  // here. Doing so while reading rebuilds ReaderScreen through an async reload,
  // which remounts this list and re-applies initialScrollIndex (now 0 from the
  // mark-read above) — yanking the reader back to the start of the opening
  // chapter. Read-state is tracked in-session via completedChapterIds, and
  // ReaderScreen refreshes these providers on exit (its PopScope).
}

class _PageLoc {
  const _PageLoc(this.imageUrl);
  final String imageUrl;
}

_PageLoc? _locate(int globalIndex, List<_LoadedChapter> loaded) {
  int cumulative = 0;
  for (final entry in loaded) {
    final n = entry.pages.pages.length;
    if (globalIndex < cumulative + n) {
      return _PageLoc(entry.pages.pages[globalIndex - cumulative]);
    }
    cumulative += n;
  }
  return null;
}
