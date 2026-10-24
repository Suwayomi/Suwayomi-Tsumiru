// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_android_volume_keydown/flutter_android_volume_keydown.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../constants/reader_keyboard_shortcuts.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_initial_overlay_tile/reader_initial_overlay_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_last_page_swipe_tile/reader_last_page_swipe_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_swipe_toggle_tile/reader_swipe_chapter_toggle_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_volume_tap_invert_tile/reader_volume_tap_invert_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import '../../../../settings/presentation/reader/widgets/tap_zones_overlay/tap_zones_overlay.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter/missing_chapters.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../manga_details/controller/manga_details_controller.dart';
import '../controller/auto_scroll_controller.dart';
import '../controller/reader_controller.dart';
import '../utils/koreader_progress_actions.dart';
import '../utils/last_page_swipe_utils.dart';
import '../utils/reader_mode_kind.dart';
import 'chrome/reader_chrome.dart';
import 'chrome/reader_page_actions_sheet.dart';
import 'chrome/reader_settings_dialog.dart';
import 'directional_swipe_gesture_handler.dart';
import 'reader_chapter_gap_warning.dart';
import 'reader_gesture_state.dart';
import 'reader_navigation_layout/reader_navigation_layout.dart';

export 'reader_gesture_state.dart';

class ReaderInputCallbacks {
  const ReaderInputCallbacks({
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onLongPressCancel,
    required this.onNext,
    required this.onPrevious,
    required this.onNextBoundary,
    required this.onPreviousBoundary,
    required this.navigationLayout,
    required this.tapInvert,
    required this.smallerTapZones,
    this.hasNextBoundary = _noBoundaryNavigation,
    this.hasPreviousBoundary = _noBoundaryNavigation,
  });

  final VoidCallback onTap;

  /// Null omits long-press recognition so slow taps are not stolen by a no-op handler.
  final ValueChanged<Offset>? onLongPressStart;
  final ValueChanged<Offset>? onLongPressMoveUpdate;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool Function() onNextBoundary;
  final bool Function() onPreviousBoundary;
  final ReaderNavigationLayout navigationLayout;
  final TapInvert tapInvert;
  final bool smallerTapZones;

  /// Check adjacency before animating so a missing chapter cannot cause a full-page turn then bounce.
  final bool Function() hasNextBoundary;
  final bool Function() hasPreviousBoundary;
}

class ReaderInputScope extends InheritedWidget {
  const ReaderInputScope({
    super.key,
    required this.callbacks,
    required super.child,
  });

  final ReaderInputCallbacks callbacks;

  static ReaderInputCallbacks? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderInputScope>()?.callbacks;

  @override
  bool updateShouldNotify(ReaderInputScope oldWidget) =>
      callbacks != oldWidget.callbacks;
}

bool _noBoundaryNavigation() => false;

final readerChromeVisibleProvider = StateProvider.autoDispose<bool?>((Ref ref) {
  final link = ref.keepAlive();
  Timer? timer;
  ref
    ..onCancel(() {
      timer = Timer(const Duration(seconds: 2), link.close);
    })
    ..onResume(() {
      timer?.cancel();
      timer = null;
    })
    ..onDispose(() => timer?.cancel());
  return null;
});

class ReaderWrapper extends HookConsumerWidget {
  const ReaderWrapper({
    super.key,
    required this.child,
    required this.manga,
    required this.chapter,
    required this.onChanged,
    required this.currentIndex,
    required this.onNext,
    required this.onPrevious,
    this.onViewportScrollForward,
    this.onViewportScrollBackward,
    this.onToggleAutoScroll,
    this.onAutoScrollFaster,
    this.onAutoScrollSlower,
    this.onJumpToFirst,
    this.onJumpToLast,
    required this.scrollDirection,
    this.showReaderLayoutAnimation = false,
    required this.chapterPages,
    this.readerScanlatorGroup,
    this.pageController,
    this.totalPageCount,
    this.childHandlesGestures = false,
    this.isAtFirstBoundary,
    this.isAtLastBoundary,
    this.spreadPageIndexes,
    this.effectiveReaderMode,
    this.handlesOwnChapterNavigation = false,
  });
  final Widget child;
  final MangaDto manga;
  final ChapterDto chapter;
  final ValueChanged<int> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onViewportScrollForward;
  final VoidCallback? onViewportScrollBackward;
  final VoidCallback? onToggleAutoScroll;
  final VoidCallback? onAutoScrollFaster;
  final VoidCallback? onAutoScrollSlower;
  final VoidCallback? onJumpToFirst;
  final VoidCallback? onJumpToLast;
  final int currentIndex;
  final Axis scrollDirection;
  final bool showReaderLayoutAnimation;
  final ChapterPagesDto chapterPages;
  final String? readerScanlatorGroup;
  final PageController? pageController;
  final int? totalPageCount;
  final bool childHandlesGestures;
  final bool Function()? isAtFirstBoundary;
  final bool Function()? isAtLastBoundary;
  final List<int>? spreadPageIndexes;
  final ReaderMode? effectiveReaderMode;

  /// Multi-chapter hosts own boundary navigation; fall through to their callbacks instead of pushReplacement.
  final bool handlesOwnChapterNavigation;

  bool _shouldUseVerticalTransition(ReaderMode readerMode) {
    switch (readerMode) {
      case ReaderMode.singleVertical:
      case ReaderMode.continuousVertical:
      case ReaderMode.webtoon:
        return true;

      case ReaderMode.singleHorizontalLTR:
      case ReaderMode.continuousHorizontalLTR:
      case ReaderMode.singleHorizontalRTL:
      case ReaderMode.continuousHorizontalRTL:
        return false;

      case ReaderMode.defaultReader:
        return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localSync = ref.watch(
      localKoSyncProgressProvider(chapterId: chapter.id),
    );
    final handledSync = useRef(<int>{});
    final conflict = chapterPages.syncConflict;
    final localConflict = localSync.value?.syncConflict;
    final pulledChapter = localSync.value?.chapter;
    useEffect(() {
      if ((conflict == null &&
              localConflict == null &&
              pulledChapter == null) ||
          handledSync.value.contains(chapter.id)) {
        return null;
      }
      handledSync.value.add(chapter.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (conflict == null &&
            localConflict == null &&
            pulledChapter != null) {
          final count = chapterPages.pages.length;
          if (count > 0) {
            onChanged(pulledChapter.user.lastPageRead.clamp(0, count - 1));
          }
          ref.invalidate(chapterProvider(chapterId: chapter.id));
          return;
        }
        unawaited(
          applyKoSyncConflict(
            context: context,
            ref: ref,
            chapter: chapter,
            remotePage: conflict?.remotePage ?? localConflict!.remotePage,
            deviceName: conflict?.deviceName ?? localConflict!.deviceName,
            pageCount: chapterPages.pages.length,
            onJump: onChanged,
          ),
        );
      });
      return null;
    }, [chapter.id, conflict, localConflict, pulledChapter]);
    final nextPrevChapterPair = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: chapter.id,
        readerScanlatorGroup: readerScanlatorGroup,
      ),
    );
    final invertTap = ref.watch(invertTapProvider).ifNull();

    // Use horizontal seeking on landscape phones unless overridden; force-horizontal always wins.
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscapePhone =
        screenSize.shortestSide < 600 && screenSize.width > screenSize.height;
    final forceHorizontalSeekbar = ref
        .watch(forceHorizontalSeekbarProvider)
        .ifNull(false);
    final landscapeVerticalSeekbar = ref
        .watch(landscapeVerticalSeekbarProvider)
        .ifNull(false);
    final showSideSeekBar =
        scrollDirection == Axis.vertical &&
        !forceHorizontalSeekbar &&
        (!isLandscapePhone || landscapeVerticalSeekbar);
    final useBottomSeekBar = !showSideSeekBar;

    final bool volumeTap = ref.watch(volumeTapProvider).ifNull();
    final bool volumeTapInvert = ref.watch(volumeTapInvertProvider).ifNull();

    final double localMangaReaderPadding =
        ref.watch(readerPaddingKeyProvider) ?? DBKeys.readerPadding.initial;

    final bool readerSwipeChapterToggle =
        ref.watch(swipeChapterToggleProvider) ?? DBKeys.swipeToggle.initial;

    final bool lastPageSwipeEnabled =
        ref.watch(lastPageSwipeEnabledProvider) ??
        DBKeys.lastPageSwipeEnabled.initial;

    final sessionVisibility = ref.watch(readerChromeVisibleProvider);
    final visibility = useState(
      sessionVisibility ?? ref.read(readerInitialOverlayProvider).ifNull(),
    );
    final utilsBarExpanded = useState(false);
    final mangaReaderPadding = useState(
      manga.metaData.readerPadding ?? localMangaReaderPadding,
    );

    final mangaReaderMode =
        manga.metaData.readerMode ?? ReaderMode.defaultReader;
    final mangaReaderNavigationLayout =
        manga.metaData.readerNavigationLayout ??
        ReaderNavigationLayout.defaultNavigation;
    final mangaTapInvert = manga.metaData.readerTapInvert;

    final defaultReaderMode = ref.watch(readerModeKeyProvider);

    final settingsResolvedReaderMode = useMemoized(
      () => LastPageSwipeUtils.resolveActualReaderMode(
        mangaReaderMode: mangaReaderMode,
        defaultReaderMode: defaultReaderMode,
      ),
      [mangaReaderMode, defaultReaderMode],
    );
    final resolvedReaderMode =
        effectiveReaderMode ?? settingsResolvedReaderMode;
    final providerContainer = ProviderScope.containerOf(context, listen: false);
    final prefetchClosers = useRef(<int, List<VoidCallback>>{});

    final showReaderModePopup = useCallback(
      () => showDialog(
        context: context,
        builder: (context) => RadioListPopup<ReaderMode>(
          optionList: ReaderMode.values,
          getOptionTitle: (value) => value.toLocale(context),
          value: mangaReaderMode,
          title: context.l10n.readerMode,
          onChange: (enumValue) async {
            if (context.mounted) Navigator.pop(context);
            await AsyncValue.guard(
              () => ref
                  .read(mangaBookRepositoryProvider)
                  .patchMangaMeta(
                    mangaId: manga.id,
                    key: MangaMetaKeys.readerMode.key,
                    value: enumValue.name,
                  ),
            );
            ref.invalidate(mangaWithIdProvider(mangaId: manga.id));
          },
        ),
        animationStyle: context.motionStyle,
      ),
      [mangaReaderMode],
    );

    useEffect(() {
      var disposed = false;
      void syncVisibility() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (disposed) return;
          ref.read(readerChromeVisibleProvider.notifier).state =
              visibility.value;
        });
      }

      syncVisibility();
      visibility.addListener(syncVisibility);
      return () {
        disposed = true;
        visibility.removeListener(syncVisibility);
      };
    }, [visibility]);

    useEffect(() {
      return () {
        for (final closers in prefetchClosers.value.values) {
          for (final close in closers) {
            close();
          }
        }
        prefetchClosers.value.clear();
      };
    }, []);

    useEffect(
      () {
        final adjacentIds = <int>{};

        final pair = nextPrevChapterPair;
        final pageCount = chapterPages.pages.length;
        if (isPagedReaderMode(resolvedReaderMode) &&
            pair != null &&
            pageCount > 0) {
          if (currentIndex >= pageCount - 2) {
            final next = pair.first;
            if (next != null) adjacentIds.add(next.id);
          }
          if (currentIndex <= 1) {
            final previous = pair.second;
            if (previous != null) adjacentIds.add(previous.id);
          }
        }

        void closePrefetch(int chapterId) {
          final closers = prefetchClosers.value.remove(chapterId);
          if (closers == null) return;
          for (final close in closers) {
            close();
          }
        }

        for (final chapterId in [...prefetchClosers.value.keys]) {
          if (!adjacentIds.contains(chapterId)) closePrefetch(chapterId);
        }

        void prefetchChapter(int chapterId) {
          if (prefetchClosers.value.containsKey(chapterId)) return;
          final chapterSubscription = providerContainer
              .listen<AsyncValue<ChapterDto?>>(
                chapterProvider(chapterId: chapterId),
                (_, _) {},
                fireImmediately: true,
              );
          final pagesSubscription = providerContainer
              .listen<AsyncValue<ChapterPagesDto?>>(
                chapterPagesProvider(chapterId: chapterId),
                (_, _) {},
                fireImmediately: true,
              );
          prefetchClosers.value[chapterId] = [
            chapterSubscription.close,
            pagesSubscription.close,
          ];
        }

        for (final chapterId in adjacentIds) {
          prefetchChapter(chapterId);
        }
        return null;
      },
      [
        resolvedReaderMode,
        nextPrevChapterPair?.first?.id,
        nextPrevChapterPair?.second?.id,
        currentIndex,
        chapterPages.pages.length,
      ],
    );


    final canSwipeAcrossChapterBoundary =
        lastPageSwipeEnabled || readerSwipeChapterToggle;

    final gapConfirmationPending = useRef(false);
    void navigateWithGapConfirmation(
      ChapterDto target,
      VoidCallback navigate, {
      required bool forward,
      bool visualTransitionShown = false,
    }) {
      if (gapConfirmationPending.value) return;
      final (higher, lower) = forward
          ? (target.chapterNumber, chapter.chapterNumber)
          : (chapter.chapterNumber, target.chapterNumber);
      final count = visualTransitionShown
          ? 0
          : chapterGap(higher: higher, lower: lower);
      if (count == 0) {
        navigate();
        return;
      }
      gapConfirmationPending.value = true;
      // Stop auto-motion before modal prompts because timers keep running behind routes.
      ref.read(autoScrollActiveProvider.notifier).stop();
      unawaited(() async {
        try {
          final confirmed = await confirmReaderChapterGap(context, count);
          if (confirmed && context.mounted) navigate();
        } finally {
          gapConfirmationPending.value = false;
        }
      }());
    }

    bool pushNextChapter({bool visualTransitionShown = false}) {
      final target = nextPrevChapterPair?.first;
      if (target == null) return false;
      final transVertical = _shouldUseVerticalTransition(resolvedReaderMode);
      final toPrev = isRTLReaderMode(resolvedReaderMode);
      navigateWithGapConfirmation(
        target,
        () => ReaderRoute(
          mangaId: manga.id,
          chapterId: target.id,
          transVertical: transVertical,
          toPrev: toPrev,
          readerScanlatorGroup: readerScanlatorGroup,
        ).pushReplacement(context),
        forward: true,
        visualTransitionShown: visualTransitionShown,
      );
      return true;
    }

    // Backward boundary crossings use openAtEnd; explicit previous-chapter commands resume saved progress.
    bool pushPreviousChapter({
      bool openAtEnd = false,
      bool visualTransitionShown = false,
    }) {
      final target = nextPrevChapterPair?.second;
      if (target == null) return false;
      final transVertical = _shouldUseVerticalTransition(resolvedReaderMode);
      final toPrev = !isRTLReaderMode(resolvedReaderMode);
      navigateWithGapConfirmation(
        target,
        () => ReaderRoute(
          mangaId: manga.id,
          chapterId: target.id,
          transVertical: transVertical,
          toPrev: toPrev,
          openAtEnd: openAtEnd,
          readerScanlatorGroup: readerScanlatorGroup,
        ).pushReplacement(context),
        forward: false,
        visualTransitionShown: visualTransitionShown,
      );
      return true;
    }

    bool tryNextChapter() {
      if (handlesOwnChapterNavigation) return false;
      if (!canSwipeAcrossChapterBoundary) return false;
      return pushNextChapter(
        visualTransitionShown:
            childHandlesGestures && isPagedReaderMode(resolvedReaderMode),
      );
    }

    bool tryPreviousChapter() {
      if (handlesOwnChapterNavigation) return false;
      if (!canSwipeAcrossChapterBoundary) return false;
      return pushPreviousChapter(
        openAtEnd: true,
        visualTransitionShown:
            childHandlesGestures && isPagedReaderMode(resolvedReaderMode),
      );
    }

    final onReaderNext = useCallback(
      () {
        if (gapConfirmationPending.value) return;
        final isAtLastPage =
            isAtLastBoundary?.call() ??
            currentIndex >= chapterPages.pages.length - 1;
        if (isAtLastPage && tryNextChapter()) {
          return;
        }
        onNext();
      },
      [
        lastPageSwipeEnabled,
        readerSwipeChapterToggle,
        currentIndex,
        chapterPages.pages.length,
        nextPrevChapterPair,
        isAtLastBoundary,
        tryNextChapter,
        onNext,
      ],
    );

    final onReaderPrevious = useCallback(
      () {
        if (gapConfirmationPending.value) return;
        final isAtFirstPage = isAtFirstBoundary?.call() ?? currentIndex <= 0;
        if (isAtFirstPage && tryPreviousChapter()) {
          return;
        }
        onPrevious();
      },
      [
        lastPageSwipeEnabled,
        readerSwipeChapterToggle,
        currentIndex,
        nextPrevChapterPair,
        isAtFirstBoundary,
        tryPreviousChapter,
        onPrevious,
      ],
    );

    final onNextChapter = useCallback(() {
      pushNextChapter();
    }, [nextPrevChapterPair, manga.id, resolvedReaderMode]);

    final onPreviousChapter = useCallback(() {
      pushPreviousChapter(openAtEnd: true);
    }, [nextPrevChapterPair, manga.id, resolvedReaderMode]);

    // Keep a managed focus node to restore focus after settings dismissal.
    final readerFocusNode = useFocusNode(debugLabel: 'reader-scroll');
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (readerFocusNode.context != null &&
            !readerFocusNode.hasPrimaryFocus) {
          readerFocusNode.requestFocus();
        }
      });
      return null;
    }, const []);

    useEffect(() {
      StreamSubscription<HardwareButton>? subscription;
      if (volumeTap) {
        subscription = FlutterAndroidVolumeKeydown.stream.listen(
          (event) => (switch (event) {
            HardwareButton.volume_up =>
              volumeTapInvert ? onReaderNext() : onReaderPrevious(),
            HardwareButton.volume_down =>
              volumeTapInvert ? onReaderPrevious() : onReaderNext(),
          }),
        );
      }
      return () => subscription?.cancel();
    }, [volumeTap, volumeTapInvert, onReaderNext, onReaderPrevious]);

    return Theme(
      data: context.theme.copyWith(
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor:
            (ref.watch(readerBackgroundColorKeyProvider) ??
                    DBKeys.readerBackgroundColor.initial
                        as ReaderBackgroundColor)
                .color(context),
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: Shortcuts.manager(
                manager: readerShortcutManager(
                  scrollDirection,
                  isRtl: isRTLReaderMode(resolvedReaderMode),
                  autoScrollSupported: onToggleAutoScroll != null,
                ),
                child: Actions(
                  actions: {
                    PreviousScrollIntent: CallbackAction<PreviousScrollIntent>(
                      onInvoke: (intent) =>
                          invertTap ? onReaderNext() : onReaderPrevious(),
                    ),
                    NextScrollIntent: CallbackAction<NextScrollIntent>(
                      onInvoke: (intent) =>
                          invertTap ? onReaderPrevious() : onReaderNext(),
                    ),
                    PreviousChapterIntent:
                        CallbackAction<PreviousChapterIntent>(
                          onInvoke: (intent) {
                            if (!pushPreviousChapter()) onReaderPrevious();
                            return null;
                          },
                        ),
                    NextChapterIntent: CallbackAction<NextChapterIntent>(
                      onInvoke: (intent) {
                        if (!pushNextChapter()) onReaderNext();
                        return null;
                      },
                    ),
                    HideQuickOpenIntent: CallbackAction<HideQuickOpenIntent>(
                      onInvoke: (HideQuickOpenIntent intent) {
                        visibility.value = !visibility.value;
                        return null;
                      },
                    ),
                    // Without a viewport callback, fall back to page navigation; down always means down regardless of tap inversion.
                    ViewportScrollForwardIntent:
                        CallbackAction<ViewportScrollForwardIntent>(
                          onInvoke: (intent) {
                            (onViewportScrollForward ?? onReaderNext)();
                            return null;
                          },
                        ),
                    ViewportScrollBackwardIntent:
                        CallbackAction<ViewportScrollBackwardIntent>(
                          onInvoke: (intent) {
                            (onViewportScrollBackward ?? onReaderPrevious)();
                            return null;
                          },
                        ),
                    AutoScrollToggleIntent:
                        CallbackAction<AutoScrollToggleIntent>(
                          onInvoke: (intent) {
                            onToggleAutoScroll?.call();
                            return null;
                          },
                        ),
                    AutoScrollFasterIntent:
                        CallbackAction<AutoScrollFasterIntent>(
                          onInvoke: (intent) {
                            onAutoScrollFaster?.call();
                            return null;
                          },
                        ),
                    AutoScrollSlowerIntent:
                        CallbackAction<AutoScrollSlowerIntent>(
                          onInvoke: (intent) {
                            onAutoScrollSlower?.call();
                            return null;
                          },
                        ),
                    FirstPageIntent: CallbackAction<FirstPageIntent>(
                      onInvoke: (intent) {
                        onJumpToFirst?.call();
                        return null;
                      },
                    ),
                    LastPageIntent: CallbackAction<LastPageIntent>(
                      onInvoke: (intent) {
                        onJumpToLast?.call();
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    focusNode: readerFocusNode,
                    child: Listener(
                      child: RepaintBoundary(
                        child: ReaderView(
                          onNextChapterCommand: () => pushNextChapter(),
                          onPreviousChapterCommand: () =>
                              pushPreviousChapter(openAtEnd: true),
                          toggleVisibility: () {
                            final gate = ref.read(
                              readerTapArrestsFlingProvider.notifier,
                            );
                            // Consume and clear the fling-arrest flag so it cannot suppress a later paged-reader tap.
                            if (gate.state) {
                              gate.state = false;
                              return;
                            }
                            visibility.value = !visibility.value;
                          },
                          scrollDirection: scrollDirection,
                          mangaId: manga.id,
                          readerScanlatorGroup: readerScanlatorGroup ?? '',
                          mangaReaderPadding: mangaReaderPadding.value,
                          onNext: onReaderNext,
                          onPrevious: onReaderPrevious,
                          onNextBoundary: tryNextChapter,
                          onPreviousBoundary: tryPreviousChapter,
                          hasNextBoundary: () =>
                              canSwipeAcrossChapterBoundary &&
                              nextPrevChapterPair?.first != null,
                          hasPreviousBoundary: () =>
                              canSwipeAcrossChapterBoundary &&
                              nextPrevChapterPair?.second != null,
                          mangaReaderNavigationLayout:
                              mangaReaderNavigationLayout,
                          mangaTapInvert: mangaTapInvert,
                          prevNextChapterPair: nextPrevChapterPair,
                          readerSwipeChapterToggle: readerSwipeChapterToggle,
                          lastPageSwipeEnabled: lastPageSwipeEnabled,
                          resolvedReaderMode: resolvedReaderMode,
                          currentIndex: currentIndex,
                          spreadPageIndexes: spreadPageIndexes,
                          chapterPages: chapterPages,
                          showReaderLayoutAnimation: showReaderLayoutAnimation,
                          pageController: pageController,
                          childHandlesGestures: childHandlesGestures,
                          child: _wrapWithBoundaryDetection(
                            child,
                            lastPageSwipeEnabled,
                            readerSwipeChapterToggle,
                            onNextChapter,
                            onPreviousChapter,
                            resolvedReaderMode,
                            scrollDirection,
                            childHandlesGestures,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ReaderChrome(
                readerScanlatorGroup: readerScanlatorGroup ?? '',
                manga: manga,
                chapter: chapter,
                chapterPages: chapterPages,
                currentIndex: currentIndex,
                totalPageCount: totalPageCount,
                visibility: visibility,
                utilsBarExpanded: utilsBarExpanded,
                useBottomSeekBar: useBottomSeekBar,
                showSideSeekBar: showSideSeekBar,
                scrollDirection: scrollDirection,
                onPreviousChapter: nextPrevChapterPair?.second != null
                    ? () => pushPreviousChapter()
                    : null,
                onNextChapter: nextPrevChapterPair?.first != null
                    ? () => pushNextChapter()
                    : null,
                resolvedReaderMode: resolvedReaderMode,
                autoScrollSupported: onToggleAutoScroll != null,
                reverseSeekBar: isRTLReaderMode(resolvedReaderMode),
                onChanged: onChanged,
                onOpenSettings: () async {
                  await showReaderSettingsSheet(
                    context: context,
                    ref: ref,
                    mangaId: manga.id,
                    visibility: visibility,
                    readerPadding: mangaReaderPadding,
                  );
                  // The reader may have been closed while the sheet was open —
                  // the focus node is disposed by then, so guard before using it.
                  if (!context.mounted) return;
                  // Don't steal focus from e.g. the quick-open search field.
                  final focus = FocusManager.instance.primaryFocus;
                  final editing = focus?.context?.widget is EditableText;
                  if (!editing) readerFocusNode.requestFocus();
                },
                onOpenReaderMode: showReaderModePopup,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapWithBoundaryDetection(
    Widget child,
    bool lastPageSwipeEnabled,
    bool readerSwipeChapterToggle,
    VoidCallback onNextChapter,
    VoidCallback onPreviousChapter,
    ReaderMode resolvedReaderMode,
    Axis scrollDirection,
    bool childHandlesGestures,
  ) {
    if (childHandlesGestures ||
        !lastPageSwipeEnabled ||
        readerSwipeChapterToggle) {
      return child;
    }

    return _BoundarySwipeDetector(
      chapterPages: chapterPages,
      onNextChapter: onNextChapter,
      onPreviousChapter: onPreviousChapter,
      resolvedReaderMode: resolvedReaderMode,
      scrollDirection: scrollDirection,
      lastPageSwipeEnabled: lastPageSwipeEnabled,
      child: child,
    );
  }
}

class _BoundarySwipeDetector extends StatefulWidget {
  const _BoundarySwipeDetector({
    required this.child,
    required this.chapterPages,
    required this.onNextChapter,
    required this.onPreviousChapter,
    required this.resolvedReaderMode,
    required this.scrollDirection,
    required this.lastPageSwipeEnabled,
  });

  final Widget child;
  final ChapterPagesDto chapterPages;
  final VoidCallback onNextChapter;
  final VoidCallback onPreviousChapter;
  final ReaderMode resolvedReaderMode;
  final Axis scrollDirection;
  final bool lastPageSwipeEnabled;

  @override
  State<_BoundarySwipeDetector> createState() => _BoundarySwipeDetectorState();
}

class _BoundarySwipeDetectorState extends State<_BoundarySwipeDetector> {
  bool _isAtMaxExtent = false;
  bool _isAtMinExtent = false;
  DateTime? _maxExtentReachedTime;
  DateTime? _minExtentReachedTime;
  bool _edgeNavTriggered = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollUpdateNotification &&
            notification.depth == 0) {
          final metrics = notification.metrics;
          _checkScrollAttemptAtBoundary(metrics);
        }

        if (notification is OverscrollNotification && notification.depth == 0) {
          _handleWebtoonOverscroll(notification);
        }

        return false;
      },
      child: widget.child,
    );
  }

  void _checkScrollAttemptAtBoundary(ScrollMetrics metrics) {
    if (metrics is PageMetrics) {
      // Use display extent for the last index; spreads/splits make raw page count differ from item count.
      final currentPage = metrics.page?.round() ?? 0;
      final lastPageIndex = metrics.viewportDimension > 0
          ? (metrics.maxScrollExtent / metrics.viewportDimension).round()
          : (widget.chapterPages.pages.length - 1);

      final bool atLastPage = currentPage >= lastPageIndex;
      final bool atFirstPage = currentPage <= 0;

      const double kOverscrollThreshold = 10.0;

      if (widget.lastPageSwipeEnabled) {
        if (atLastPage &&
            metrics.pixels - metrics.maxScrollExtent > kOverscrollThreshold) {
          if (!_edgeNavTriggered) {
            _edgeNavTriggered = true;
            widget.onNextChapter();
          }
        } else if (atFirstPage &&
            metrics.minScrollExtent - metrics.pixels > kOverscrollThreshold) {
          if (!_edgeNavTriggered) {
            _edgeNavTriggered = true;
            widget.onPreviousChapter();
          }
        }
      }

      _isAtMaxExtent = metrics.pixels >= metrics.maxScrollExtent;
      _isAtMinExtent = metrics.pixels <= metrics.minScrollExtent;

      if (!_isAtMaxExtent && !_isAtMinExtent) {
        _edgeNavTriggered = false;
      }
    } else {
      final wasAtMaxExtent = _isAtMaxExtent;
      final wasAtMinExtent = _isAtMinExtent;

      _isAtMaxExtent = metrics.pixels >= metrics.maxScrollExtent;
      _isAtMinExtent = metrics.pixels <= metrics.minScrollExtent;

      if (_isAtMaxExtent && !wasAtMaxExtent) {
        _maxExtentReachedTime = DateTime.now();
      }
      if (_isAtMinExtent && !wasAtMinExtent) {
        _minExtentReachedTime = DateTime.now();
      }

      if (!_isAtMaxExtent && wasAtMaxExtent) {
        _maxExtentReachedTime = null;
      }
      if (!_isAtMinExtent && wasAtMinExtent) {
        _minExtentReachedTime = null;
      }

      if (!_isAtMaxExtent && !_isAtMinExtent) {
        _edgeNavTriggered = false;
      }
    }
  }

  void _handleWebtoonOverscroll(OverscrollNotification notification) {
    if (!widget.lastPageSwipeEnabled) {
      return;
    }

    final now = DateTime.now();
    final bool isPagedReader = notification.metrics is PageMetrics;
    final int triggerDelayMs = isPagedReader ? 50 : 300;

    const double kImmediateThreshold = 2.0;

    if (isPagedReader) {
      if (_isAtMaxExtent && notification.overscroll > kImmediateThreshold) {
        if (!_edgeNavTriggered) {
          _edgeNavTriggered = true;
          widget.onNextChapter();
        }
        return;
      }
      if (_isAtMinExtent && notification.overscroll < -kImmediateThreshold) {
        if (!_edgeNavTriggered) {
          _edgeNavTriggered = true;
          widget.onPreviousChapter();
        }
        return;
      }
    }

    if (_isAtMaxExtent && notification.overscroll > 0) {
      if (_maxExtentReachedTime != null &&
          now.difference(_maxExtentReachedTime!).inMilliseconds >
              triggerDelayMs) {
        if (!_edgeNavTriggered) {
          _edgeNavTriggered = true;
          widget.onNextChapter();
        }
      }
    }

    if (_isAtMinExtent && notification.overscroll < 0) {
      if (_minExtentReachedTime != null &&
          now.difference(_minExtentReachedTime!).inMilliseconds >
              triggerDelayMs) {
        if (!_edgeNavTriggered) {
          _edgeNavTriggered = true;
          widget.onPreviousChapter();
        }
      }
    }
  }
}

class ReaderView extends HookConsumerWidget {
  const ReaderView({
    super.key,
    required this.toggleVisibility,
    required this.scrollDirection,
    required this.mangaId,
    required this.readerScanlatorGroup,
    required this.mangaReaderPadding,
    required this.onNext,
    required this.onPrevious,
    required this.prevNextChapterPair,
    required this.mangaReaderNavigationLayout,
    this.mangaTapInvert,
    this.onNextBoundary = _noBoundaryNavigation,
    this.onPreviousBoundary = _noBoundaryNavigation,
    this.hasNextBoundary = _noBoundaryNavigation,
    this.hasPreviousBoundary = _noBoundaryNavigation,
    required this.readerSwipeChapterToggle,
    required this.lastPageSwipeEnabled,
    required this.resolvedReaderMode,
    required this.currentIndex,
    this.spreadPageIndexes,
    required this.chapterPages,
    required this.child,
    this.showReaderLayoutAnimation = false,
    this.pageController,
    this.childHandlesGestures = false,
    this.onNextChapterCommand,
    this.onPreviousChapterCommand,
  });

  final VoidCallback toggleVisibility;
  final VoidCallback? onNextChapterCommand;
  final VoidCallback? onPreviousChapterCommand;
  final Axis scrollDirection;
  final int mangaId;
  final String readerScanlatorGroup;
  final double mangaReaderPadding;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool Function() onNextBoundary;
  final bool Function() onPreviousBoundary;
  final bool Function() hasNextBoundary;
  final bool Function() hasPreviousBoundary;
  final ({ChapterDto? first, ChapterDto? second})? prevNextChapterPair;
  final ReaderNavigationLayout mangaReaderNavigationLayout;
  final TapInvert? mangaTapInvert;
  final bool readerSwipeChapterToggle;
  final bool lastPageSwipeEnabled;
  final ReaderMode resolvedReaderMode;
  final int currentIndex;
  final List<int>? spreadPageIndexes;
  final ChapterPagesDto chapterPages;
  final bool showReaderLayoutAnimation;
  final Widget child;
  final PageController? pageController;
  final bool childHandlesGestures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageActionsOpen = useState(false);

    final readWithLongTap =
        ref.watch(readWithLongTapProvider) ?? DBKeys.readWithLongTap.initial;

    Widget content = Padding(
      padding: EdgeInsets.symmetric(
        vertical:
            context.height *
            (scrollDirection != Axis.vertical ? mangaReaderPadding : 0),
        horizontal:
            context.width *
            (scrollDirection == Axis.vertical ? mangaReaderPadding : 0),
      ),
      child: child,
    );

    final PageController? controller =
        pageController ??
        (PrimaryScrollController.of(context) is PageController
            ? PrimaryScrollController.of(context) as PageController
            : null);

    void handleLongPressStart(Offset position) {
      if (pageActionsOpen.value || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      pageActionsOpen.value = true;
      unawaited(
        showReaderPageActionsSheet(
          context: context,
          ref: ref,
          chapterPages: chapterPages,
          pageIndex: currentIndex,
          spreadPageIndexes: spreadPageIndexes,
        ).whenComplete(() {
          if (context.mounted) pageActionsOpen.value = false;
        }),
      );
    }

    void handleLongPressCancel() {
      // Flag-first + canPop so this and the sheet's own dismissal can't
      // double-pop (which trips the scope assertion) or pop the reader itself.
      if (pageActionsOpen.value &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == false &&
          Navigator.of(context).canPop()) {
        pageActionsOpen.value = false;
        unawaited(Navigator.of(context).maybePop());
      }
    }

    final resolvedNavigationLayout = effectiveNavigationLayout(
      ref,
      mode: resolvedReaderMode,
      seriesOverride: mangaReaderNavigationLayout,
    );

    // Latch the one-shot hint at open so clearing its flag cannot remove the overlay in the same frame.
    final overlayAlways = ref.watch(showTapZonesOverlayProvider).ifNull();
    final unseenAtOpen = useRef<bool?>(null);
    unseenAtOpen.value ??= ref.read(tapZonesOverlayUnseenProvider).ifNull(true);
    final zonesAreVisible =
        resolvedNavigationLayout != ReaderNavigationLayout.disabled;
    final showZonesOnOpen =
        showReaderLayoutAnimation &&
        zonesAreVisible &&
        (overlayAlways || unseenAtOpen.value!);
    useEffect(() {
      if (!showZonesOnOpen || !unseenAtOpen.value!) return null;
      // Guard context.mounted: a reader popped in the same turn would write
      // through a disposed ref.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        // Latch too, or turning the hint off and on again replays the one look.
        unseenAtOpen.value = false;
        ref.read(tapZonesOverlayUnseenProvider.notifier).update(false);
      });
      return null;
    }, [showZonesOnOpen]);

    final resolvedTapInvert = effectiveTapInvert(
      ref,
      mode: resolvedReaderMode,
      layout: resolvedNavigationLayout,
      seriesOverride: mangaTapInvert,
    );

    if (childHandlesGestures) {
      final layout = resolvedNavigationLayout;
      final tapInvert = resolvedTapInvert;
      final smallerTapZones = ref.watch(smallerTapZonesProvider) ?? false;
      content = ReaderInputScope(
        callbacks: ReaderInputCallbacks(
          onTap: toggleVisibility,
          onLongPressStart: readWithLongTap ? handleLongPressStart : null,
          onLongPressCancel: readWithLongTap ? handleLongPressCancel : null,
          onNext: onNext,
          onPrevious: onPrevious,
          onNextBoundary: onNextBoundary,
          onPreviousBoundary: onPreviousBoundary,
          hasNextBoundary: hasNextBoundary,
          hasPreviousBoundary: hasPreviousBoundary,
          navigationLayout: layout,
          tapInvert: tapInvert,
          smallerTapZones: smallerTapZones,
        ),
        child: content,
      );
    } else {
      content = DirectionalSwipeGestureHandler(
        onNextChapterCommand: onNextChapterCommand,
        onPreviousChapterCommand: onPreviousChapterCommand,
        readerScanlatorGroup: readerScanlatorGroup,
        onTap: toggleVisibility,
        onLongPressStart: readWithLongTap
            ? (details) => handleLongPressStart(details.localPosition)
            : null,
        scrollDirection: scrollDirection,
        readerSwipeChapterToggle: readerSwipeChapterToggle,
        lastPageSwipeEnabled: lastPageSwipeEnabled,
        resolvedReaderMode: resolvedReaderMode,
        currentIndex: currentIndex,
        chapterPages: chapterPages,
        mangaId: mangaId,
        prevNextChapterPair: prevNextChapterPair,
        onNextPage: onNext,
        onPreviousPage: onPrevious,
        pageController: controller,
        child: content,
      );
    }

    return Stack(
      children: [
        content,
        // Paged routes taps through ReaderInputScope, so this overlay is
        // display-only there.
        IgnorePointer(
          ignoring: childHandlesGestures,
          child: ReaderNavigationLayoutWidget(
            onNext: onNext,
            onPrevious: onPrevious,
            navigationLayout: resolvedNavigationLayout,
            tapInvert: resolvedTapInvert,
            showReaderLayoutAnimation: showZonesOnOpen,
          ),
        ),
      ],
    );
  }
}
