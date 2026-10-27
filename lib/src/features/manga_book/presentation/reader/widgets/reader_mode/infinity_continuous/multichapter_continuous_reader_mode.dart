// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../../../constants/db_keys.dart';
import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/app_utils.dart';
import '../../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../../utils/platform/platform_runtime.dart';
import '../../../../../../../widgets/server_image.dart';
import '../../../../../../../widgets/zoom/scroll_offset_to_scroll_controller.dart';
import '../../../../../../history/presentation/history_controller.dart';
import '../../../../../../offline/data/offline_download_providers.dart';
import '../../../../../../offline/data/offline_repository.dart';
import '../../../../../../settings/presentation/incognito/incognito_mode.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_mouse_scroll_speed_slider/reader_mouse_scroll_speed_slider.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_scroll_animation_tile/reader_scroll_animation_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import '../../../../../../tracking/domain/track_progress_gate.dart';
import '../../../../../domain/chapter/chapter_model.dart';
import '../../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../../domain/manga/manga_model.dart';
import '../../../../manga_details/controller/manga_details_controller.dart';
import '../../../../manga_details/controller/scanlator_dedup.dart';
import '../../../controller/auto_scroll_controller.dart';
import '../../../controller/reader_controller.dart';
import '../../../controller/reader_settings_model.dart';
import '../../../utils/download_ahead.dart';
import '../../../utils/flush_progress_on_lifecycle.dart';
import '../../../utils/reader_initial_page.dart';
import '../../../utils/reader_progress_queue.dart';
import '../../mouse_wheel_speed.dart';
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

/// Next auto-scroll interval boundary; user drags yield only until that boundary.
Duration autoScrollResumeAt(Duration elapsed, int intervalSeconds) {
  if (intervalSeconds <= 0) return elapsed;
  final periodMs = intervalSeconds * 1000;
  return Duration(
    milliseconds: ((elapsed.inMilliseconds ~/ periodMs) + 1) * periodMs,
  );
}

typedef _LoadedChapter = ({
  ChapterPagesDto pages,
  ChapterDto chapter,
  int chapterId,
});

/// Compensate above-viewport image resizes and re-anchor after prepends to preserve reading position.
class MultiChapterContinuousReaderMode extends HookConsumerWidget {
  const MultiChapterContinuousReaderMode({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    required this.readerScanlatorGroup,
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
  final String readerScanlatorGroup;
  final ValueSetter<int>? onPageChanged;
  final Axis scrollDirection;
  final bool reverse;
  final bool showReaderLayoutAnimation;
  final ReaderMode effectiveReaderMode;
  final bool openAtEnd;

  /// Injectable edge-overscroll cooldown because widget tests cannot advance wall-clock time.
  @visibleForTesting
  static Duration edgeAttemptCooldown = const Duration(seconds: 4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    watchDownloadAhead(ref);
    bool readerToastsEnabled() =>
        ref.read(readerFeedbackToastsProvider).ifNull(true);
    final ItemScrollController itemScrollController = useMemoized(
      () => ItemScrollController(),
    );
    final ItemPositionsListener positionsListener = useMemoized(
      () => ItemPositionsListener.create(),
    );
    final ScrollOffsetController scrollOffsetController = useMemoized(
      () => ScrollOffsetController(),
    );
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

    // Keep measured page extents across item disposal so re-entry placeholders cannot shift the viewport.
    final pageHeights = useRef<Map<String, double>>(<String, double>{});
    // Bumped each time a new ordered prefetch sweep starts, so a stale sweep
    // (from before a seek / chapter load) cancels itself.
    final prefetchGen = useRef<int>(0);
    // Suppress neighbour loads while programmatic jumps settle so transient positions cannot shift indices.
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

    final lastStartFeedbackTime = useRef<DateTime?>(null);
    final completedChapterIds = useRef<Set<int>>({});

    // Session protection: protect each chapter opened in this reader from
    // reconcile eviction. Discarded on dispose; never accumulates across sessions.
    final sessionChapterIds = useRef<Set<int>>({});
    final sessionNotifier = ref.read(sessionReadChaptersProvider.notifier);
    // Mirrored into a ref each build so the deferred callbacks below never
    // have to touch `ref` themselves — `ref` throws if it outlives the widget.
    final incognitoRef = useRef(ref.watch(incognitoModeProvider));
    incognitoRef.value = ref.watch(incognitoModeProvider);
    useEffect(() {
      var active = true;
      void doRecord(int id) {
        if (!active || incognitoRef.value) return;
        if (!sessionChapterIds.value.contains(id)) {
          sessionChapterIds.value = {...sessionChapterIds.value, id};
          // The container may be disposed before this microtask; ignore that teardown race.
          try {
            sessionNotifier.record(id);
          } catch (_) {
            // The internal UnmountedRefException type is not exported.
          }
        }
      }

      // Use a microtask so the update runs even if no further frame is scheduled.
      Future.microtask(() => doRecord(currentVisibleChapter.value.id));
      void onChanged() => doRecord(currentVisibleChapter.value.id);
      currentVisibleChapter.addListener(onChanged);
      return () {
        active = false;
        currentVisibleChapter.removeListener(onChanged);
        // Disposal may occur during build; defer and tolerate an already-disposed container.
        Future.microtask(() {
          try {
            sessionNotifier.discard(sessionChapterIds.value);
          } catch (_) {
            // The internal UnmountedRefException type is not exported.
          }
        });
      };
    }, const []);

    final lastVisibleChapterId = useRef<int>(chapter.id);
    // Top-most visible (index, leadingEdge) from the previous listener
    // tick, used to derive scroll direction so neighbour chapters load
    // only when the user scrolls TOWARD an edge — never on initial open.
    final lastTop = useRef<({int index, double edge})?>(null);

    final edgeOverscrollAccum = useRef<double>(0);
    final lastEdgeOverscrollAt = useRef<DateTime?>(null);
    final lastEdgeAttemptAt = useRef<DateTime?>(null);

    // Watch the loading chapter list and mirror it for the once-bound position listener.
    final nextPrevChapterPair =
        useRef<({ChapterDto? first, ChapterDto? second})?>(null);
    nextPrevChapterPair.value = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: currentVisibleChapter.value.id,
        readerScanlatorGroup: readerScanlatorGroup,
      ),
    );
    // Do not latch a missing neighbour across list reloads; offline lists may omit server chapters.
    useEffect(
      () {
        if (nextPrevChapterPair.value?.first != null) {
          hasReachedEnd.value = false;
        }
        if (nextPrevChapterPair.value?.second != null) {
          hasReachedStart.value = false;
        }
        return null;
      },
      [
        nextPrevChapterPair.value?.first?.id,
        nextPrevChapterPair.value?.second?.id,
      ],
    );

    // Record progress for the visible chapter through the offline-safe write path.
    final progressDebounce = useRef<Timer?>(null);
    final latestProgress = useRef<({int chapterId, int rel, int generation})?>(
      null,
    );
    final allChaptersForFlush = useRef<List<ChapterDto>?>(null);
    allChaptersForFlush.value = ref
        .watch(mangaChapterListProvider(mangaId: manga.id))
        .value;

    _LoadedChapter? loadedById(int id) {
      for (final c in loadedRef.value) {
        if (c.chapterId == id) return c;
      }
      return null;
    }

    ReaderProgressQueue progressQueue(int id) => ref
        .read(readerProgressQueuesProvider)
        .putIfAbsent(id, ReaderProgressQueue.new);

    Future<void> writeVisibleProgress(
      int chapterId,
      int rel,
      int generation,
    ) async {
      if (progressQueue(chapterId).generation != generation ||
          progressQueue(chapterId).syncing) {
        return;
      }
      if (!context.mounted) return;
      if (ref.read(incognitoModeProvider)) return;
      // A late partial write must not undo the final state recorded at a chapter boundary.
      if (chapterId != currentVisibleChapter.value.id) return;
      if (completedChapterIds.value.contains(chapterId)) return;
      final lc = loadedById(chapterId);
      if (lc == null) return;
      if (lc.chapter.user.isRead.ifNull()) return;
      final pageCount = lc.pages.pages.length;
      final completed = rel >= (pageCount - 1) && pageCount > 0;
      // Don't write a lower page than what's already saved (at-open snapshot),
      // unless we're completing the chapter.
      if (!completed &&
          lc.chapter.user.lastPageRead.getValueOnNullOrNegative() >= rel) {
        return;
      }
      final progressResult = await recordReadingProgress(
        ref,
        mangaId: manga.id,
        chapterId: chapterId,
        lastPageRead: rel,
        isRead: completed,
        generation: generation,
      );
      if (!context.mounted ||
          progressQueue(chapterId).generation != generation) {
        return;
      }
      // Surface failed pushes for online-only users because they have no dirty row to retry.
      if (progressResult.hasError) {
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
      }
      if (completed && !completedChapterIds.value.contains(chapterId)) {
        completedChapterIds.value = {...completedChapterIds.value, chapterId};
        unawaited(
          maybeTrackProgressOnReadFetch(
            ref.read,
            mangaId: manga.id,
            isRead: true,
            manual: false,
          ),
        );
        unawaited(
          noteChapterFinishedInReader(
            ref,
            mangaId: manga.id,
            chapterId: chapterId,
          ),
        );
      }
      // Defer invalidation outside scroll/layout notifications to avoid writes during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.invalidate(readingHistoryProvider);
      });
    }

    void scheduleVisibleProgress(int chapterId, int rel) {
      unawaited(
        downloadAhead(
          ref,
          manga.id,
          chapterId,
          rel,
          readerScanlatorGroup: readerScanlatorGroup,
        ).catchError((Object error) {
          debugPrint('$error');
        }),
      );

      if (ref.read(incognitoModeProvider)) return;
      final queue = progressQueue(chapterId);
      if (queue.syncing) return;
      final generation = queue.generation;
      latestProgress.value = (
        chapterId: chapterId,
        rel: rel,
        generation: generation,
      );
      progressDebounce.value?.cancel();
      final pageCount = loadedById(chapterId)?.pages.pages.length ?? 0;
      if (rel >= (pageCount - 1) && pageCount > 0) {
        // Completion: write immediately so finishing a chapter isn't lost to a
        // pending debounce.
        unawaited(writeVisibleProgress(chapterId, rel, generation));
      } else {
        progressDebounce.value = Timer(
          const Duration(seconds: 2),
          () => unawaited(writeVisibleProgress(chapterId, rel, generation)),
        );
      }
    }

    // Skip the restore emit so opening on the last page does not complete the chapter.
    final initialProgressConsumed = useRef<bool>(false);
    useEffect(() {
      if (!initialProgressConsumed.value) {
        initialProgressConsumed.value = true;
        return null;
      }
      scheduleVisibleProgress(
        currentVisibleChapter.value.id,
        currentChapterPageIndex.value,
      );
      return null;
    }, [currentChapterPageIndex.value, currentVisibleChapter.value.id]);

    // Capture DB and flags before teardown; flush directly to the dirty catalog without touching ref.
    final offlineEnabledForFlush = ref.read(offlineEnabledProvider);
    final offlineDbForFlush = offlineEnabledForFlush
        ? ref.read(offlineDatabaseProvider)
        : null;
    final progressQueuesForFlush = ref.read(readerProgressQueuesProvider);
    final incognitoForFlush = ref.read(incognitoModeProvider);
    useEffect(() {
      return () {
        progressDebounce.value?.cancel();
        final p = latestProgress.value;
        if (p == null) return;
        final queue = progressQueuesForFlush.putIfAbsent(
          p.chapterId,
          ReaderProgressQueue.new,
        );
        if (queue.syncing || p.generation != queue.generation) return;
        if (completedChapterIds.value.contains(p.chapterId)) return;
        if (incognitoForFlush || offlineDbForFlush == null) return;
        // A teardown racing completion must preserve the completed state rather than write unread.
        final lc = loadedById(p.chapterId);
        final pageCount = lc?.pages.pages.length ?? 0;
        final isCompletion = pageCount > 0 && p.rel >= pageCount - 1;
        final chapterIds = isCompletion
            ? expandIdsForDuplicates(allChaptersForFlush.value, [p.chapterId])
            : [p.chapterId];
        for (final chapterId in chapterIds) {
          unawaited(
            offlineDbForFlush
                .setChapterProgress(
                  chapterId,
                  lastPageRead: p.rel,
                  // Never un-read on a teardown flush: only a completion marks read.
                  isRead: isCompletion ? true : null,
                )
                .catchError((_) {}),
          );
        }
      };
    }, const []);

    // Flush to the server on hidden/exit; desktop close may skip pop/dispose and teardown is offline-only.
    useFlushProgressOnAppLifecycle(() async {
      progressDebounce.value?.cancel();
      final p = latestProgress.value;
      if (p == null) return;
      if (completedChapterIds.value.contains(p.chapterId)) return;
      await writeVisibleProgress(p.chapterId, p.rel, p.generation);
    });

    final bool isAnimationEnabled = ref
        .watch(readerScrollAnimationProvider)
        .ifNull(true);
    final bool animatePageTransitions = ref
        .watch(readerEffectiveSettingsProvider(manga.id))
        .animatePageTransitions;
    final bool isPinchToZoomEnabled = ref
        .watch(longStripPinchToZoomProvider)
        .ifNull(true);
    final bool isDoubleTapZoomEnabled = ref
        .watch(longStripDoubleTapToZoomProvider)
        .ifNull(true);
    final bool isZoomOutDisabled = ref
        .watch(longStripDisableZoomOutProvider)
        .ifNull();
    // Reset zoom state on mount/unmount so a previous session cannot disable chapter swipes.
    useEffect(() {
      // Capture the notifier before teardown; ref is unsafe during hook disposal.
      final notifier = ref.read(readerIsZoomedInProvider.notifier);
      notifier.state = false;
      return () => notifier.state = false;
    }, const []);
    final bool cropBorders = ref.watch(cropBordersWebtoonProvider).ifNull();
    final bool alwaysShowTransition = ref
        .watch(alwaysShowChapterTransitionProvider)
        .ifNull(true);
    final WebtoonScaleType scaleType =
        ref.watch(webtoonScaleTypeKeyProvider) ?? WebtoonScaleType.fitScreen;
    // Original-size pages cap themselves at native width, so the strip width limit must not apply.
    final bool pagesAtNaturalSize = scaleType == WebtoonScaleType.originalSize;
    final bool widthLimitInPixels = ref
        .watch(longStripWidthLimitUsePixelsProvider)
        .ifNull();
    // Clamped on read: the sliders enforce their ranges but a corrupted pref
    // must not collapse the layout.
    final int widthLimitPercent =
        (ref.watch(longStripWidthLimitPercentProvider) ??
                DBKeys.longStripWidthLimitPercent.initial as int)
            .clamp(10, 100);
    final int widthLimitPx =
        (ref.watch(longStripWidthLimitPxProvider) ??
                DBKeys.longStripWidthLimitPx.initial as int)
            .clamp(200, 2000);
    // 100% is the off position; a px cap wider than the window is naturally
    // inert through the min() below.
    final double widthLimit = pagesAtNaturalSize
        ? double.infinity
        : widthLimitInPixels
        ? widthLimitPx.toDouble()
        : widthLimitPercent >= 100
        ? double.infinity
        : context.width * widthLimitPercent / 100;
    final double maxContentWidth = math.min(
      scaleType.maxContentWidth(context.width, context.height),
      widthLimit,
    );
    final bool isHorizontal = scrollDirection == Axis.horizontal;
    final double mainAxisExtent = isHorizontal ? context.width : context.height;
    // Width limits apply only to vertical strips; horizontal strips use viewport height.
    final double crossAxisExtent = isHorizontal
        ? context.height
        : maxContentWidth;
    // Once-bound callbacks read live layout parameters so old closures cannot reserve stale widths.
    final layoutParams = useRef<({bool naturalSize, double columnWidth})>((
      naturalSize: pagesAtNaturalSize,
      columnWidth: crossAxisExtent,
    ));
    layoutParams.value = (
      naturalSize: pagesAtNaturalSize,
      columnWidth: crossAxisExtent,
    );
    final ReaderScrollAmount scrollAmount =
        ref.watch(readerScrollAmountKeyProvider) ??
        DBKeys.readerScrollAmount.initial as ReaderScrollAmount;

    final bool autoScrollActive = ref.watch(autoScrollActiveProvider);
    final bool smoothAutoScroll =
        ref.watch(smoothAutoScrollProvider) ??
        DBKeys.smoothAutoScroll.initial as bool;
    final int autoScrollIntervalSeconds =
        ref.watch(autoScrollIntervalSecondsProvider) ??
        DBKeys.autoScrollIntervalSeconds.initial as int;
    // Set around every auto-scroll-driven jump so the manual-scroll listener
    // below doesn't mistake the engine's own motion for a user drag.
    final programmaticScroll = useRef<bool>(false);
    final lastAutoScrollTick = useRef<Duration>(Duration.zero);
    final autoScrollPausedUntil = useRef<Duration>(Duration.zero);
    // Tracked between ScrollStart/ScrollEnd so a touch landing mid-coast can be
    // told from one landing on a still page.
    final stripInMotion = useRef<bool>(false);
    final bool chromeVisible = ref.watch(readerChromeVisibleProvider) ?? false;

    // Cache decoded aspect-derived extents before display so pages cannot resize on arrival.
    Future<void> decodeAndCacheHeight(String url, int gen) async {
      if (pageHeights.value.containsKey(url)) return;
      final provider = serverPageImageProvider(ref, url);
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ImageInfo>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (e, st) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final info = await completer.future;
      info.dispose();
      final intrinsicSize = await serverPageIntrinsicSize(ref, url);
      final w = intrinsicSize.width;
      final h = intrinsicSize.height;
      // Reject a superseded decode so its old width cannot enter the reservation cache.
      if (w > 0 && h > 0 && context.mounted && prefetchGen.value == gen) {
        // Read via layoutParams, not closure capture, so a sweep started by
        // an old build still reserves at the current width.
        final layout = layoutParams.value;
        final crossAxisSize = isHorizontal
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).width;
        final renderedCrossAxis = layout.naturalSize
            ? math.min(
                isHorizontal ? h.toDouble() : w.toDouble(),
                crossAxisSize,
              )
            : layout.columnWidth;
        // Cross/main axes are width/height vertically and height/width horizontally.
        pageHeights.value[url] = isHorizontal
            ? renderedCrossAxis * w / h
            : renderedCrossAxis * h / w;
      }
    }

    // Prefetch in reading order; a new seek or chapter load cancels the old sweep by generation.
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
            await decodeAndCacheHeight(urls[i], gen);
          } catch (_) {}
        }
      });
    }

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

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) prefetchPagesFrom(currentChapterPageIndex.value);
      });
      return () => adjustIdleTimer.value?.cancel();
    }, const []);

    // Suppress neighbour loading while a programmatic jump settles.
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
      // Reseed decode order after a seek so newly visible strips do not resize on landing.
      prefetchPagesFrom(index);
    }

    // Clear stale extents and re-anchor after scale/width changes; skip the initial sweep.
    final lastLayoutKey = useRef<(WebtoonScaleType, double)?>(null);
    useEffect(() {
      final key = (scaleType, crossAxisExtent);
      final previous = lastLayoutKey.value;
      lastLayoutKey.value = key;
      if (previous == null || previous == key) return null;
      prefetchGen.value++;
      pageHeights.value.clear();
      markScrollAdjusting();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        // Recomputed here, not at effect time: a prepend landing this same
        // frame shifts every index under the pending jump.
        final anchor = currentGlobalIndex();
        if (itemScrollController.isAttached) {
          jumpToIndex(index: anchor);
        } else {
          // jumpToIndex would early-return without re-seeding — never leave
          // the gen bump above with no replacement sweep.
          prefetchPagesFrom(anchor);
        }
      });
      return null;
    }, [scaleType, crossAxisExtent]);


    Future<void> loadNextChapter(ChapterDto next) async {
      if (loadingNext.value || hasReachedEnd.value) return;
      if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
      loadingNext.value = true;
      try {
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showLoadingNextChapterFeedback(
            context,
            next.name,
          );
        }
        // Hold the autoDispose neighbour provider until fetch completion so timeout retries can reuse its result.
        final sub = ref.listenManual(
          chapterPagesProvider(chapterId: next.id),
          (_, _) {},
        );
        final fetch = ref.read(chapterPagesProvider(chapterId: next.id).future);
        // Release the hold when the FETCH ends, not when the timeout fires —
        // a late result must still land in the cache for the next attempt.
        fetch.whenComplete(sub.close).ignore();
        final ChapterPagesDto? pages;
        try {
          pages = await fetch.timeout(const Duration(seconds: 15));
        } on TimeoutException {
          return;
        }
        if (pages == null) {
          ref.invalidate(chapterPagesProvider(chapterId: next.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == next.id)) return;
        loadedChapters.value = [
          ...loadedChapters.value,
          (pages: pages, chapter: next, chapterId: next.id),
        ];
        prefetchPagesFrom(currentGlobalIndex());
        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showNextChapterLoadedFeedback(
            context,
            next.name,
          );
        }
      } catch (_) {
        // Invalidate transient failures so the next gesture can retry.
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
            context,
            prev.name,
          );
        }
        final sub = ref.listenManual(
          chapterPagesProvider(chapterId: prev.id),
          (_, _) {},
        );
        final fetch = ref.read(chapterPagesProvider(chapterId: prev.id).future);
        fetch.whenComplete(sub.close).ignore();
        final ChapterPagesDto? pages;
        try {
          pages = await fetch.timeout(const Duration(seconds: 15));
        } on TimeoutException {
          return;
        }
        if (pages == null) {
          ref.invalidate(chapterPagesProvider(chapterId: prev.id));
          return;
        }
        if (loadedRef.value.any((e) => e.chapterId == prev.id)) return;

        final newPageCount = pages.pages.length;

        // Keep unclamped anchor depth; jumpTo supports only [0, 1] alignment, so restore pixel depth separately.
        final positions = positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
        int? anchorIndex;
        double anchorLeadingEdge = 0.0;
        for (final p in positions) {
          if (p.itemTrailingEdge > 0) {
            anchorIndex = p.index;
            anchorLeadingEdge = p.itemLeadingEdge;
            break;
          }
        }
        anchorIndex ??= positions.isNotEmpty ? positions.first.index : null;
        double intoAnchorPixels = 0;
        try {
          if (anchorLeadingEdge < 0) {
            intoAnchorPixels =
                -anchorLeadingEdge *
                scrollOffsetController.position.viewportDimension;
          }
        } catch (_) {
        }

        loadedChapters.value = [
          (pages: pages, chapter: prev, chapterId: prev.id),
          ...loadedChapters.value,
        ];
        // Prepending shifts indices, invalidating the previous direction sample.
        lastTop.value = null;

        // Re-anchor the shifted item first, then restore its pixel depth after layout settles.
        if (anchorIndex != null) {
          final target = anchorIndex + newPageCount;
          // Guard the re-anchor jump too: its settle motion must not be read
          // as a scroll back to the top that prepends yet another chapter.
          markScrollAdjusting();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            jumpToIndex(index: target, alignment: 0.0);
            if (intoAnchorPixels > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  final pos = scrollOffsetController.position;
                  pos.jumpTo(
                    (pos.pixels + intoAnchorPixels).clamp(
                      pos.minScrollExtent,
                      pos.maxScrollExtent,
                    ),
                  );
                } catch (_) {}
              });
            }
          });
        }

        if (context.mounted && readerToastsEnabled()) {
          InfinityContinuousFeedback.showPreviousChapterLoadedFeedback(
            context,
            prev.name,
          );
        }
      } catch (_) {
        // Invalidate transient failures so the next gesture can retry.
        ref.invalidate(chapterPagesProvider(chapterId: prev.id));
      } finally {
        loadingPrevious.value = false;
      }
    }


    useEffect(() {
      void listener() {
        final loaded = loadedRef.value;
        final total = InfinityContinuousUtils.getTotalPages(loaded);
        if (total <= 0) return;

        final positions = positionsListener.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList();
        if (positions.isEmpty) return;

        // The last page wins once its bottom reaches the viewport so short trailing pages can complete.
        final globalIdx = InfinityContinuousUtils.selectCurrentIndex(
          positions,
          total,
          minVisibleAreaThreshold:
              InfinityContinuousConfig.minVisibleAreaThreshold,
        );
        if (globalIdx == null) return;

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
              final newPos = loaded.indexWhere(
                (e) => e.chapterId == ch.chapter.id,
              );
              currentVisibleChapter.value = ch.chapter;
              lastVisibleChapterId.value = ch.chapter.id;
              if (prevPos >= 0 && newPos > prevPos) {
                final left = loaded[prevPos].chapter;
                _markChapterRead(
                  ref,
                  manga.id,
                  left,
                  loaded[prevPos].pages.pages.length,
                  completedChapterIds,
                  context,
                );
              }
            }
            break;
          }
          cumulative += count;
        }

        // Ignore jump-settling positions and clear the direction sample before resuming edge handling.
        if (isAdjustingScroll.value) {
          lastTop.value = null;
          return;
        }

        // Load neighbours only toward the scroll direction, using a visibility floor to ignore grazed page edges.
        final strictlyVisible = positions
            .where(
              (p) =>
                  InfinityContinuousUtils.calculateVisibleArea(p) >=
                  InfinityContinuousConfig.boundaryVisibleAreaThreshold,
            )
            .toList();
        final boundaryPositions = strictlyVisible.isNotEmpty
            ? strictlyVisible
            : positions;
        final minIdx = boundaryPositions
            .map((p) => p.index)
            .reduce((a, b) => a < b ? a : b);
        final maxIdx = boundaryPositions
            .map((p) => p.index)
            .reduce((a, b) => a > b ? a : b);

        final top = positions.reduce((a, b) => a.index <= b.index ? a : b);
        final prevTop = lastTop.value;
        lastTop.value = (index: top.index, edge: top.itemLeadingEdge);
        bool scrollingUp = false;
        bool scrollingDown = false;
        if (prevTop != null) {
          // Measure direction thresholds in pixels so viewport size cannot turn layout jitter into scrolling.
          double viewportHeight = 0;
          try {
            viewportHeight = scrollOffsetController.position.viewportDimension;
          } catch (_) {
            // Not laid out yet — fall back to a small-but-safe fraction.
          }
          final double eps = viewportHeight > 0
              ? InfinityContinuousConfig.boundaryScrollDirectionEpsilonPx /
                    viewportHeight
              : 0.03;
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
                context,
                lastStartFeedbackTime,
              );
            }
          }
        }
      }

      positionsListener.itemPositions.addListener(listener);
      return () => positionsListener.itemPositions.removeListener(listener);
    }, const []);


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
      // Jump before background decoding so neighbour loads cannot shift the pending target indices.
      markScrollAdjusting();
      lastTop.value = null;
      itemScrollController.jumpTo(index: globalIndex, alignment: 0);
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
      if (isAnimationEnabled && !context.reduceMotion) {
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
        final double offset = viewport * scrollAmount.fraction * sign;
        if (animatePageTransitions && !context.reduceMotion) {
          scrollOffsetController.animateScroll(
            offset: offset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          pos.jumpTo(
            (pos.pixels + offset).clamp(
              pos.minScrollExtent,
              pos.maxScrollExtent,
            ),
          );
        }
      } catch (_) {
      }
    }

    // Auto-scroll pauses for chrome and user drags; resume at the next interval boundary.

    bool atLastLoadedPage() =>
        hasReachedEnd.value &&
        currentGlobalIndex() >=
            InfinityContinuousUtils.getTotalPages(loadedChapters.value) - 1;

    void onAutoScrollTick(Duration elapsed) {
      if (!itemScrollController.isAttached) return;
      final dtMs = (elapsed - lastAutoScrollTick.value).inMilliseconds;
      lastAutoScrollTick.value = elapsed;
      if (dtMs <= 0) return;
      if (elapsed < autoScrollPausedUntil.value) return;
      try {
        final pos = scrollOffsetController.position;
        final interval =
            ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        final delta = autoScrollDelta(
          viewport: pos.viewportDimension,
          intervalSeconds: interval,
          dtMs: dtMs,
        );
        final target = pos.pixels + (reverse ? -delta : delta);
        final atEnd = reverse
            ? target <= pos.minScrollExtent
            : target >= pos.maxScrollExtent;
        if (atEnd && hasReachedEnd.value) {
          ref.read(autoScrollActiveProvider.notifier).stop();
          return;
        }
        programmaticScroll.value = true;
        pos.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
      } catch (_) {
      } finally {
        // Always release the programmatic-scroll guard, including when a jump throws.
        programmaticScroll.value = false;
      }
    }

    // Create the ticker once; useSingleTickerProvider permits only one createTicker call per hook.
    final autoScrollTickerProvider = useSingleTickerProvider();
    final autoScrollTicker = useMemoized(
      () => autoScrollTickerProvider.createTicker(onAutoScrollTick),
      const [],
    );

    useEffect(() {
      if (autoScrollActive && smoothAutoScroll && !chromeVisible) {
        lastAutoScrollTick.value = Duration.zero;
        autoScrollPausedUntil.value = Duration.zero;
        if (!autoScrollTicker.isActive) autoScrollTicker.start();
      } else if (autoScrollTicker.isActive) {
        autoScrollTicker.stop();
      }
      return null;
    }, [autoScrollActive, smoothAutoScroll, chromeVisible]);

    useEffect(
      () {
        Timer? timer;
        if (autoScrollActive && !smoothAutoScroll && !chromeVisible) {
          timer = Timer.periodic(Duration(seconds: autoScrollIntervalSeconds), (
            _,
          ) {
            if (stripInMotion.value) return;
            if (atLastLoadedPage()) {
              ref.read(autoScrollActiveProvider.notifier).stop();
              return;
            }
            programmaticScroll.value = true;
            try {
              handlePageNavigation(isNext: true);
            } finally {
              programmaticScroll.value = false;
            }
          });
        }
        return () => timer?.cancel();
      },
      [
        autoScrollActive,
        smoothAutoScroll,
        autoScrollIntervalSeconds,
        chromeVisible,
      ],
    );

    // Dispose the shared ticker only on widget teardown, after both mode effects.
    useEffect(() {
      return () {
        if (autoScrollTicker.isActive) autoScrollTicker.stop();
        autoScrollTicker.dispose();
      };
    }, const []);

    // Stop auto-scroll in background so it cannot keep writing progress unseen.
    useEffect(() {
      final listener = AppLifecycleListener(
        onHide: () => ref.read(autoScrollActiveProvider.notifier).stop(),
        onPause: () => ref.read(autoScrollActiveProvider.notifier).stop(),
      );
      return listener.dispose;
    }, const []);


    final total = InfinityContinuousUtils.getTotalPages(loadedChapters.value);

    Widget capWidth(Widget page) {
      final containerExtent = isHorizontal ? context.height : context.width;
      if (crossAxisExtent >= containerExtent) return page;
      return Center(
        child: isHorizontal
            ? SizedBox(height: crossAxisExtent, child: page)
            : SizedBox(width: crossAxisExtent, child: page),
      );
    }

    Widget buildEndOfStrip(BuildContext context) {
      final pair = nextPrevChapterPair.value;
      final trailingSpace =
          MediaQuery.viewPaddingOf(context).bottom +
          InfinityContinuousConfig.endOfStripSpace;
      return Flex(
        direction: scrollDirection,
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfinityContinuousChapterSeparator(
                chapterName: loadedChapters.value.last.chapter.name,
                isChapterStart: false,
              ),
              // A null pair means the chapter list hasn't loaded yet.
              if (pair != null && pair.first == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    context.l10n.noMoreChaptersAhead,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.theme.colorScheme.onSurface.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Gap(trailingSpace),
        ],
      );
    }

    Widget buildItem(BuildContext context, int index) {
      final loc = _locate(index, loadedChapters.value);
      final fallbackMainAxisExtent = isHorizontal
          ? mainAxisExtent * InfinityContinuousConfig.horizontalPageWidthRatio
          : mainAxisExtent * InfinityContinuousConfig.verticalPageHeightRatio;
      if (loc == null) {
        return isHorizontal
            ? SizedBox(width: fallbackMainAxisExtent)
            : SizedBox(height: fallbackMainAxisExtent);
      }
      // Reserve measured extent, then sibling average, then one viewport so decode cannot shift earlier pages.
      final measured = pageHeights.value;
      final double? avgExtent = measured.isEmpty
          ? null
          : measured.values.reduce((a, b) => a + b) / measured.length;
      final placeholderExtent =
          measured[loc.imageUrl] ?? avgExtent ?? fallbackMainAxisExtent;
      final fit = isHorizontal ? BoxFit.fitHeight : BoxFit.fitWidth;
      Widget placeholderBox({Widget? child}) => isHorizontal
          ? SizedBox(
              width: placeholderExtent,
              height: double.infinity,
              child: child,
            )
          : SizedBox(
              height: placeholderExtent,
              width: double.infinity,
              child: child,
            );
      final page = ServerImage(
        showReloadButton: true,
        fit: fit,
        appendApiToUrl: false,
        cropBorders: cropBorders,
        // Decode at display size to avoid sampling full-resolution webtoon textures every frame.
        memCacheWidth: isHorizontal
            ? null
            : (crossAxisExtent * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1 << 20),
        memCacheHeight: isHorizontal
            ? (crossAxisExtent * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1 << 20)
            : null,
        imageUrl: loc.imageUrl,
        progressIndicatorBuilder: (_, _, progress) => placeholderBox(
          child: Center(
            child: CircularProgressIndicator(value: progress.progress),
          ),
        ),
        imageBuilder: (context, imageProvider) {
          final image = Image(
            image: imageProvider,
            fit: pagesAtNaturalSize ? BoxFit.scaleDown : fit,
            width: pagesAtNaturalSize
                ? null
                : (isHorizontal ? null : double.infinity),
            height: pagesAtNaturalSize
                ? null
                : (isHorizontal ? double.infinity : null),
            // Deleted offline files need stable-extent placeholders when the user scrolls back.
            errorBuilder: (context, error, stackTrace) => placeholderBox(
              child: Center(
                child: Icon(
                  FluentIcons.image_off_24_regular,
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // Reserve offline page extent until decode; file:// bypasses the network progress placeholder.
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame == null && !wasSynchronouslyLoaded) {
                return placeholderBox();
              }
              // Measure decoded images only so re-entry reserves real extent rather than placeholder size.
              return MeasureSize(
                onChange: (size) {
                  final extent = isHorizontal ? size.width : size.height;
                  if (extent <= 0) return;
                  pageHeights.value[loc.imageUrl] = extent;
                },
                child: child,
              );
            },
          );
          // Center loosens cross-axis constraints so scaleDown can shrink to native size.
          return pagesAtNaturalSize ? Center(child: image) : image;
        },
      );
      if (index != total - 1) return page;
      final endOfStrip = buildEndOfStrip(context);
      return Flex(
        direction: scrollDirection,
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        children: reverse ? [endOfStrip, page] : [page, endOfStrip],
      );
    }

    // Only continuousVertical exposes gaps; horizontal legacy modes use the webtoon no-gap default.
    final pageGap = effectiveReaderMode == ReaderMode.continuousVertical
        ? const Gap(kLongStripPageGap)
        : const SizedBox.shrink();

    Widget buildSeparator(BuildContext context, int index) {
      if (loadedChapters.value.length <= 1) return pageGap;
      if (!InfinityContinuousUtils.isChapterBoundary(
        index,
        loadedChapters.value,
      )) {
        return pageGap;
      }
      final info = InfinityContinuousChapterSeparator.getSeparatorInfo(
        index,
        loadedChapters.value,
      );
      if (info == null) return pageGap;
      return InfinityContinuousChapterSeparator(
        chapterName: info.chapterName,
        isChapterStart: info.isChapterStart,
        alwaysShow: alwaysShowTransition,
        gapCount: info.gapCount,
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
      minCacheExtent: isHorizontal
          ? context.width * InfinityContinuousConfig.horizontalCacheMultiplier
          : context.height * InfinityContinuousConfig.verticalCacheMultiplier,
      itemBuilder: (context, index) => capWidth(buildItem(context, index)),
      separatorBuilder: (context, index) =>
          capWidth(buildSeparator(context, index)),
    );

    // User drags yield until the next interval; exclude guarded programmatic jumps.
    final autoScrollAwareList = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (!programmaticScroll.value &&
            notification.direction != ScrollDirection.idle &&
            ref.read(autoScrollActiveProvider)) {
          autoScrollPausedUntil.value = autoScrollResumeAt(
            lastAutoScrollTick.value,
            autoScrollIntervalSeconds,
          );
        }
        return false;
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          stripInMotion.value = false;
          return false;
        },
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (_) {
            if (!programmaticScroll.value) stripInMotion.value = true;
            return false;
          },
          child: positionedList,
        ),
      ),
    );

    // Clamped drags emit no position change; use accumulated overscroll with cooldown to trigger boundary loads.
    final edgeAwareList = NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (isAdjustingScroll.value || programmaticScroll.value) return false;
        final now = DateTime.now();
        // A pause resets the pull: separate gestures don't add up.
        if (lastEdgeOverscrollAt.value == null ||
            now.difference(lastEdgeOverscrollAt.value!) >
                const Duration(milliseconds: 800)) {
          edgeOverscrollAccum.value = 0;
        }
        lastEdgeOverscrollAt.value = now;
        edgeOverscrollAccum.value += n.overscroll;
        if (edgeOverscrollAccum.value.abs() < 48) return false;
        if (lastEdgeAttemptAt.value != null &&
            now.difference(lastEdgeAttemptAt.value!) < edgeAttemptCooldown) {
          return false;
        }
        final positions = positionsListener.itemPositions.value;
        if (positions.isEmpty) return false;
        var minIdx = positions.first.index;
        var maxIdx = positions.first.index;
        for (final p in positions) {
          if (p.index < minIdx) minIdx = p.index;
          if (p.index > maxIdx) maxIdx = p.index;
        }
        if (edgeOverscrollAccum.value < 0 && minIdx <= 0) {
          final prev = nextPrevChapterPair.value?.second;
          if (prev != null) {
            lastEdgeAttemptAt.value = now;
            edgeOverscrollAccum.value = 0;
            loadPreviousChapter(prev);
          }
        } else if (edgeOverscrollAccum.value > 0 &&
            maxIdx >=
                InfinityContinuousUtils.getTotalPages(loadedRef.value) - 1) {
          final next = nextPrevChapterPair.value?.first;
          if (next != null) {
            lastEdgeAttemptAt.value = now;
            edgeOverscrollAccum.value = 0;
            loadNextChapter(next);
          }
        }
        return false;
      },
      child: autoScrollAwareList,
    );

    final mouseScrollSpeed =
        ref.watch(readerMouseScrollSpeedKeyProvider) ??
        DBKeys.readerMouseScrollSpeed.initial;
    final wheelAware = isKeyboardRuntime
        ? MouseWheelSpeed(
            speed: mouseScrollSpeed,
            axis: scrollDirection,
            reverse: reverse,
            positionOf: () => scrollOffsetController.position,
            child: edgeAwareList,
          )
        : edgeAwareList;

    // Pointer-down is the last moment the fling is still live before the drag
    // cancels it, so the arrest decision is snapshotted here.
    final flingAwareChild = Listener(
      onPointerDown: (_) {
        final arrests = stripInMotion.value && !programmaticScroll.value;
        final gate = ref.read(readerTapArrestsFlingProvider.notifier);
        if (gate.state != arrests) gate.state = arrests;
      },
      child: wheelAware,
    );

    final child = AppUtils.wrapOn(
      !kIsWeb &&
              (Platform.isAndroid || Platform.isIOS) &&
              (isPinchToZoomEnabled || isDoubleTapZoomEnabled)
          ? (Widget child) => ReaderZoomView(
              controller: zoomScrollController,
              scrollAxis: scrollDirection,
              reverse: reverse,
              maxScale: InfinityContinuousConfig.maxZoomScale,
              minScale: isZoomOutDisabled ? 1 : 0.5,
              pinchEnabled: isPinchToZoomEnabled,
              doubleTapToZoom: isDoubleTapZoomEnabled,
              onScaleChanged: (scale) {
                final notifier = ref.read(readerIsZoomedInProvider.notifier);
                final zoomed = scale > 1.01;
                if (notifier.state != zoomed) notifier.state = zoomed;
              },
              child: child,
            )
          : null,
      flingAwareChild,
    );

    return ReaderWrapper(
      readerScanlatorGroup: readerScanlatorGroup,
      scrollDirection: scrollDirection,
      chapterPages: InfinityContinuousUtils.createChapterPagesDto(
        loadedChapters.value,
        currentVisibleChapter.value,
        chapterPages,
      ),
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
      // Use the shared jump path to keep page index, prefetch, and scroll-adjust guards in sync.
      onJumpToFirst: () => jumpToChapterRelative(0),
      onJumpToLast: () => jumpToChapterRelative(
        (loadedById(currentVisibleChapter.value.id)?.pages.pages.length ??
                chapterPages.pages.length) -
            1,
      ),
      onToggleAutoScroll: () =>
          ref.read(autoScrollActiveProvider.notifier).toggle(),
      onAutoScrollFaster: () {
        final cur =
            ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        ref
            .read(autoScrollIntervalSecondsProvider.notifier)
            .update((cur - 1).clamp(1, 30));
      },
      onAutoScrollSlower: () {
        final cur =
            ref.read(autoScrollIntervalSecondsProvider) ??
            DBKeys.autoScrollIntervalSeconds.initial as int;
        ref
            .read(autoScrollIntervalSecondsProvider.notifier)
            .update((cur + 1).clamp(1, 30));
      },
      child: child,
    );
  }
}

void _markChapterRead(
  WidgetRef ref,
  int mangaId,
  ChapterDto chapter,
  int pageCount,
  ObjectRef<Set<int>> completedChapterIds,
  BuildContext context,
) {
  if (ref.read(incognitoModeProvider)) return;
  if (ref.read(readerProgressQueuesProvider)[chapter.id]?.syncing ?? false) {
    return;
  }
  if (chapter.user.isRead.ifNull()) return;
  if (completedChapterIds.value.contains(chapter.id)) return;
  completedChapterIds.value = {...completedChapterIds.value, chapter.id};
  // Persist boundary completion locally before pushing so offline reads remain queued.
  unawaited(
    recordReadingProgress(
      ref,
      mangaId: mangaId,
      chapterId: chapter.id,
      lastPageRead: (pageCount - 1).clamp(0, 1 << 31),
      isRead: true,
    ).then((progressResult) {
      if (!context.mounted) return;
      // A failed boundary push has no dirty row to retry for online-only users.
      if (progressResult.hasError) {
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
      }
      unawaited(
        maybeTrackProgressOnReadFetch(
          ref.read,
          mangaId: mangaId,
          isRead: true,
          manual: false,
        ),
      );
      unawaited(
        noteChapterFinishedInReader(
          ref,
          mangaId: mangaId,
          chapterId: chapter.id,
        ),
      );
    }),
  );
  // Do not invalidate chapter providers mid-read: remounting resets scroll; refresh on reader exit.
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
