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
import '../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_initial_overlay_tile/reader_initial_overlay_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_last_page_swipe_tile/reader_last_page_swipe_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_swipe_toggle_tile/reader_swipe_chapter_toggle_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import '../../../../settings/presentation/reader/widgets/tap_zones_overlay/tap_zones_overlay.dart';
import '../../../../settings/presentation/reader/widgets/reader_volume_tap_invert_tile/reader_volume_tap_invert_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/chapter_page/chapter_page_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../manga_details/controller/manga_details_controller.dart';
import '../controller/reader_controller.dart';
import '../utils/last_page_swipe_utils.dart';
import '../utils/reader_mode_kind.dart';
import 'chrome/reader_chrome.dart';
import 'chrome/reader_page_actions_sheet.dart';
import 'chrome/reader_settings_dialog.dart';
import 'directional_swipe_gesture_handler.dart';
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

  /// Null when nothing consumes a long press. The recognizers are then never
  /// registered, so a slow tap stays a tap instead of losing the gesture arena
  /// to a handler that would have done nothing with it.
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

  /// Whether an adjacent chapter exists to move to — lets the paged viewport
  /// decide before animating, so it doesn't slide a page fully off-screen only
  /// to bounce back when there's no chapter there.
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

/// Whether the reader chrome is on screen. Public so the long strip can hold
/// auto-scroll while it is up.
final readerChromeVisibleProvider =
    StateProvider.autoDispose<bool?>((Ref ref) {
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
  final PageController? pageController;
  final int? totalPageCount;
  final bool childHandlesGestures;
  final bool Function()? isAtFirstBoundary;
  final bool Function()? isAtLastBoundary;
  final List<int>? spreadPageIndexes;
  final ReaderMode? effectiveReaderMode;

  /// When true the child (a multi-chapter host) crosses chapter boundaries
  /// itself inside one continuous pager, so the reading-flow boundary must NOT
  /// `pushReplacement` a fresh chapter — it falls through to the child's
  /// onNext/onPrevious instead.
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
    final nextPrevChapterPair = ref.watch(
      getNextAndPreviousChaptersProvider(
        mangaId: manga.id,
        chapterId: chapter.id,
      ),
    );
    final invertTap = ref.watch(invertTapProvider).ifNull();

    // Webtoon (vertical) normally uses the vertical side seek bar, but on a phone
    // in landscape there's no vertical room for it to be usable — fall back to
    // the standard horizontal bottom bar. Two General-tab prefs
    // adjust the chain: force-horizontal wins everywhere; the landscape
    // sub-toggle keeps the side seekbar on a landscape phone.
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscapePhone =
        screenSize.shortestSide < 600 && screenSize.width > screenSize.height;
    final forceHorizontalSeekbar =
        ref.watch(forceHorizontalSeekbarProvider).ifNull(false);
    final landscapeVerticalSeekbar =
        ref.watch(landscapeVerticalSeekbarProvider).ifNull(false);
    final showSideSeekBar = scrollDirection == Axis.vertical &&
        !forceHorizontalSeekbar &&
        (!isLandscapePhone || landscapeVerticalSeekbar);
    // Exactly one seekbar: whenever the side seekbar is out, the horizontal
    // bottom one serves (paged, landscape fallback, forced horizontal).
    final useBottomSeekBar = !showSideSeekBar;

    final bool volumeTap = ref.watch(volumeTapProvider).ifNull();
    final bool volumeTapInvert = ref.watch(volumeTapInvertProvider).ifNull();

    final double localMangaReaderPadding =
        ref.watch(readerPaddingKeyProvider) ?? DBKeys.readerPadding.initial;

    final bool readerSwipeChapterToggle =
        ref.watch(swipeChapterToggleProvider) ?? DBKeys.swipeToggle.initial;

    final bool lastPageSwipeEnabled = ref.watch(lastPageSwipeEnabledProvider) ??
        DBKeys.lastPageSwipeEnabled.initial;

    final sessionVisibility = ref.watch(readerChromeVisibleProvider);
    final visibility = useState(
      sessionVisibility ?? ref.read(readerInitialOverlayProvider).ifNull(),
    );
    // Komikku-style utils bar (auto-scroll control): starts collapsed each
    // reader open, unlike chrome visibility which persists across chapters.
    final utilsBarExpanded = useState(false);
    final mangaReaderPadding =
        useState(manga.metaData.readerPadding ?? localMangaReaderPadding);

    final mangaReaderMode =
        manga.metaData.readerMode ?? ReaderMode.defaultReader;
    final mangaReaderNavigationLayout = manga.metaData.readerNavigationLayout ??
        ReaderNavigationLayout.defaultNavigation;
    // Per-series 4-value tap-invert; null lets the layout fall back to the
    // global compat value (new key ?? legacy bool).
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
              () => ref.read(mangaBookRepositoryProvider).patchMangaMeta(
                    mangaId: manga.id,
                    key: MangaMetaKeys.readerMode.key,
                    value: enumValue.name,
                  ),
            );
            ref.invalidate(mangaWithIdProvider(mangaId: manga.id));
          },
        ),
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

    useEffect(() {
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
        final chapterSubscription =
            providerContainer.listen<AsyncValue<ChapterDto?>>(
          chapterProvider(chapterId: chapterId),
          (_, __) {},
          fireImmediately: true,
        );
        final pagesSubscription =
            providerContainer.listen<AsyncValue<ChapterPagesDto?>>(
          chapterPagesProvider(chapterId: chapterId),
          (_, __) {},
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
    }, [
      resolvedReaderMode,
      nextPrevChapterPair?.first?.id,
      nextPrevChapterPair?.second?.id,
      currentIndex,
      chapterPages.pages.length,
    ]);

    // NOTE: The visibility→SystemUiMode transition is now driven by
    // ReaderChrome's AnimationController status listener (Inc-1), not here.
    // edgeToEdge is requested when the controller starts going forward;
    // immersiveSticky is requested when it reaches dismissed — so the OS bars
    // move *with* the animated Material bars rather than snapping at t=0 (C1).
    // reader_screen.dart's mount/unmount immersive effect is left untouched.

    final canSwipeAcrossChapterBoundary =
        lastPageSwipeEnabled || readerSwipeChapterToggle;

    bool pushNextChapter() {
      if (nextPrevChapterPair?.first == null) return false;
      final transVertical = _shouldUseVerticalTransition(resolvedReaderMode);
      final toPrev = isRTLReaderMode(resolvedReaderMode);
      ReaderRoute(
        mangaId: manga.id,
        chapterId: nextPrevChapterPair!.first!.id,
        transVertical: transVertical,
        toPrev: toPrev,
      ).pushReplacement(context);
      return true;
    }

    // openAtEnd belongs to backward boundary crossings, where the reader is
    // still moving through the story and the last page is the next thing they
    // should see. An explicit "previous chapter" command resumes that chapter
    // instead, matching Komikku's loadPreviousChapter.
    bool pushPreviousChapter({bool openAtEnd = false}) {
      if (nextPrevChapterPair?.second == null) return false;
      final transVertical = _shouldUseVerticalTransition(resolvedReaderMode);
      final toPrev = !isRTLReaderMode(resolvedReaderMode);
      ReaderRoute(
        mangaId: manga.id,
        chapterId: nextPrevChapterPair!.second!.id,
        transVertical: transVertical,
        toPrev: toPrev,
        openAtEnd: openAtEnd,
      ).pushReplacement(context);
      return true;
    }

    bool tryNextChapter() {
      // Host owns in-window chapter crossing: don't push a fresh route; let the
      // reading-flow boundary fall through to the child's controller.
      if (handlesOwnChapterNavigation) return false;
      if (!canSwipeAcrossChapterBoundary) return false;
      return pushNextChapter();
    }

    bool tryPreviousChapter() {
      if (handlesOwnChapterNavigation) return false;
      if (!canSwipeAcrossChapterBoundary) return false;
      return pushPreviousChapter(openAtEnd: true);
    }

    final onReaderNext = useCallback(() {
      final isAtLastPage = isAtLastBoundary?.call() ??
          currentIndex >= chapterPages.pages.length - 1;
      if (isAtLastPage && tryNextChapter()) {
        return;
      }
      onNext();
    }, [
      lastPageSwipeEnabled,
      readerSwipeChapterToggle,
      currentIndex,
      chapterPages.pages.length,
      nextPrevChapterPair,
      isAtLastBoundary,
      tryNextChapter,
      onNext,
    ]);

    final onReaderPrevious = useCallback(() {
      final isAtFirstPage = isAtFirstBoundary?.call() ?? currentIndex <= 0;
      if (isAtFirstPage && tryPreviousChapter()) {
        return;
      }
      onPrevious();
    }, [
      lastPageSwipeEnabled,
      readerSwipeChapterToggle,
      currentIndex,
      nextPrevChapterPair,
      isAtFirstBoundary,
      tryPreviousChapter,
      onPrevious,
    ]);

    final onNextChapter = useCallback(() {
      pushNextChapter();
    }, [nextPrevChapterPair, manga.id, resolvedReaderMode]);

    // Feeds _BoundarySwipeDetector only: every call site is an overscroll past
    // the first page, which is a backward crossing rather than a command.
    final onPreviousChapter = useCallback(() {
      pushPreviousChapter(openAtEnd: true);
    }, [nextPrevChapterPair, manga.id, resolvedReaderMode]);

    // Managed (not autofocus) so re-requesting focus after the settings
    // sheet closes (below) has a node to hand it back to.
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
        // Reader background pref; default black.
        backgroundColor: (ref.watch(readerBackgroundColorKeyProvider) ??
                DBKeys.readerBackgroundColor.initial as ReaderBackgroundColor)
            .color(context),
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: Shortcuts.manager(
                manager: readerShortcutManager(scrollDirection,
                    isRtl: isRTLReaderMode(resolvedReaderMode),
                    autoScrollSupported: onToggleAutoScroll != null),
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
                    // Null falls back to page nav so paged/other modes that
                    // don't supply viewport scroll keep working. Intentionally
                    // ignores invertTap — arrow-down always scrolls down.
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
                    // Nullable callbacks: any non-continuous vertical mode
                    // that doesn't supply these is a safe no-op.
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
                          toggleVisibility: () {
                            final gate =
                                ref.read(readerTapArrestsFlingProvider.notifier);
                            // Cleared on use: only the long strip arms it, so a
                            // stale true would swallow taps in the paged reader.
                            if (gate.state) {
                              gate.state = false;
                              return;
                            }
                            visibility.value = !visibility.value;
                          },
                          scrollDirection: scrollDirection,
                          mangaId: manga.id,
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
            // Chrome: top bar, bottom controls, and optional side seek bar.
            // All chrome is managed by ReaderChrome, which applies the same
            // visibility conditional as before (still instant show/hide; the
            // synchronized animation is a later increment).
            Positioned.fill(
              child: ReaderChrome(
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
                onNextChapter:
                    nextPrevChapterPair?.first != null ? pushNextChapter : null,
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
      // PageView-based readers (horizontal modes). Derive the last index from
      // the scroll extent, not the raw page count, so edge-swipe chapter nav is
      // correct under double-page/split (item count != raw page count).
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
  });

  final VoidCallback toggleVisibility;
  final Axis scrollDirection;
  final int mangaId;
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

    // "Show actions on long tap" (default ON): long-press opens the
    // page-actions sheet. OFF: long-press does nothing.
    final readWithLongTap =
        ref.watch(readWithLongTapProvider) ?? DBKeys.readWithLongTap.initial;

    Widget content = Padding(
      padding: EdgeInsets.symmetric(
        vertical: context.height *
            (scrollDirection != Axis.vertical ? mangaReaderPadding : 0),
        horizontal: context.width *
            (scrollDirection == Axis.vertical ? mangaReaderPadding : 0),
      ),
      child: child,
    );

    final PageController? controller = pageController ??
        (PrimaryScrollController.of(context) is PageController
            ? PrimaryScrollController.of(context) as PageController
            : null);

    void handleLongPressStart(Offset position) {
      if (pageActionsOpen.value || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      pageActionsOpen.value = true;
      unawaited(showReaderPageActionsSheet(
        context: context,
        ref: ref,
        chapterPages: chapterPages,
        pageIndex: currentIndex,
        spreadPageIndexes: spreadPageIndexes,
      ).whenComplete(() {
        if (context.mounted) pageActionsOpen.value = false;
      }));
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

    // Komikku's showNavigationOverlayOnStart plus its new-user one-shot.
    // Read once and held, not watched: watching would clear the flag and
    // take the flash away in the same frame it was granted.
    final overlayAlways = ref.watch(showTapZonesOverlayProvider).ifNull();
    final unseenAtOpen = useRef<bool?>(null);
    unseenAtOpen.value ??= ref.read(tapZonesOverlayUnseenProvider).ifNull(true);
    // No point spending the one-shot on a layout that draws nothing.
    final zonesAreVisible =
        resolvedNavigationLayout != ReaderNavigationLayout.disabled;
    final showZonesOnOpen = showReaderLayoutAnimation &&
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
          // Off means nobody wants the gesture, so it is never claimed.
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
        onTap: toggleVisibility,
        // Null when nothing consumes it, so the recognizer is never registered
        // and a slow tap isn't lost to the long-press arena.
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
