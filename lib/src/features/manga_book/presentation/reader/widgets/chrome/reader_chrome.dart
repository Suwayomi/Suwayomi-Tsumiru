// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_left_handed_seekbar_tile/reader_left_handed_seekbar_tile.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../reader_mode/infinity_continuous/measure_size.dart';
import 'chrome_extents.dart';
import 'reader_bottom_controls.dart';
import 'reader_color_overlays.dart';
import 'reader_flash_overlay.dart';
import 'reader_side_seekbar.dart';
import 'reader_top_bar.dart';
import 'reader_utils_bar.dart';

/// UI mode while the chrome is hidden: fullscreen hides the OS bars; with
/// fullscreen OFF they stay visible (edgeToEdge) even when the chrome goes.
SystemUiMode hiddenChromeUiMode({required bool fullscreen}) =>
    fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge;

/// Stack-based host that layers the reader chrome (top bar, bottom controls,
/// side seek bar) over the viewer content.
///
/// All three chrome bars are **always mounted**. A single [AnimationController]
/// (200 ms) drives their show/hide via [SlideTransition] + [FadeTransition],
/// so top and bottom move in perfect lockstep — no more "instant-pop top,
/// sliding bottom" desync (Bug B). The slide runs the full
/// 200 ms on [Curves.fastOutSlowIn] while the fade completes faster (~150 ms
/// via an [Interval]) for a snappier feel.
///
/// The OS system-bar transition (edgeToEdge ↔ immersiveSticky) is slaved to
/// the controller's [AnimationStatus] via a status listener, so the OS bars
/// move *with* the Material bars rather than snapping at `t=0` (C1).
///
/// [visibility] (owned by [ReaderWrapper]) remains the single source of truth —
/// the controller is a pure render concern driven by a [useEffect].
///
/// [onOpenSettings] opens the 3-tab settings bottom sheet
/// (`showReaderSettingsSheet`), which replaced the old endDrawer.
class ReaderChrome extends HookConsumerWidget {
  const ReaderChrome({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    required this.currentIndex,
    required this.totalPageCount,
    required this.visibility,
    required this.utilsBarExpanded,
    required this.useBottomSeekBar,
    required this.showSideSeekBar,
    required this.scrollDirection,
    required this.nextPrevChapterPair,
    required this.resolvedReaderMode,
    required this.autoScrollSupported,
    required this.reverseSeekBar,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onOpenReaderMode,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final int currentIndex;

  /// For infinity-scroll mode; null means use [chapterPages.chapter.pageCount].
  final int? totalPageCount;

  /// Source of truth for chrome visibility (the [useState] from [ReaderWrapper]).
  /// The controller tracks this notifier; [visibility] is never written here.
  final ValueNotifier<bool> visibility;

  /// Owned by [ReaderWrapper]; toggled by [ReaderTopBar]'s tune button.
  /// Expands [ReaderUtilsBar] beneath the top bar.
  final ValueNotifier<bool> utilsBarExpanded;

  /// True when the horizontal bottom seek bar should be shown (paged / landscape).
  final bool useBottomSeekBar;

  /// True when the vertical side seek bar should be shown (webtoon / vertical,
  /// non-landscape phone).
  final bool showSideSeekBar;

  final Axis scrollDirection;
  final ({ChapterDto? first, ChapterDto? second})? nextPrevChapterPair;
  final ReaderMode resolvedReaderMode;

  /// True only in modes that actually mount an auto-scroll/auto-advance engine.
  /// The utils bar (and its toggle) is hidden otherwise, so it's never a dead
  /// control.
  final bool autoScrollSupported;
  final bool reverseSeekBar;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenReaderMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Single animation controller that drives ALL three bars ────────────────
    //
    // initialValue seeds from the current visibility so there is no flash when
    // the widget first mounts (the reader opens with chrome visible by default).
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 200),
      initialValue: visibility.value ? 1.0 : 0.0,
    );

    // A16 (targetSdk 36) forces edge-to-edge and ignores statusBar/navBar colors,
    // so we don't set them; the bars paint their own surface behind the system
    // bars. Kept: icon brightness + contrastEnforced:false (3-button nav scrim).
    final darkIcons = context.theme.colorScheme.brightness == Brightness.light;
    final readerOverlayStyle = SystemUiOverlayStyle(
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
      statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          darkIcons ? Brightness.dark : Brightness.light,
    );

    // ── C1: OS system-bar sync — driven from controller status, not raw bool ──
    //
    // Registering the listener here (not in reader_wrapper.dart) lets us tie
    // the OS-bar transition to the *actual* animation progress:
    //   • controller starts going forward → show OS bars (edgeToEdge) so the
    //     status-bar clock appears *with* the sliding Material top bar.
    //   • animation completes in reverse (dismissed) → hide OS bars
    //     (immersiveSticky) so they vanish *after* the slide-out finishes.
    //
    // The old visibility→SystemUiMode useEffect in reader_wrapper.dart has been
    // removed; this listener is now the sole driver of the toggle.
    // reader_screen.dart's mount/unmount immersive effect is left untouched —
    // it sets the initial immersiveSticky state and restores on exit; the two
    // do not conflict because reader_screen sets on mount (once) while this
    // listener updates only on animation-status transitions.
    // Fullscreen OFF keeps the OS bars up even while the chrome is hidden.
    final fullscreen = ref.watch(readerFullscreenProvider) ??
        DBKeys.readerFullscreen.initial as bool;
    useEffect(() {
      void onStatus(AnimationStatus status) {
        switch (status) {
          case AnimationStatus.forward:
            // Slide-in starting → show OS bars so they appear with the chrome.
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            SystemChrome.setSystemUIOverlayStyle(readerOverlayStyle);
          case AnimationStatus.dismissed:
            // Slide-out complete → hide OS bars after the chrome has gone.
            SystemChrome.setEnabledSystemUIMode(
              hiddenChromeUiMode(fullscreen: fullscreen),
            );
          case AnimationStatus.reverse:
          case AnimationStatus.completed:
            break;
        }
      }

      controller.addStatusListener(onStatus);

      // Sync OS bars to the initial chrome state (status listeners only fire on
      // transitions, so the first frame needs an explicit apply). Re-runs when
      // the fullscreen pref flips, so a hidden-chrome reader updates live.
      SystemChrome.setEnabledSystemUIMode(
        visibility.value
            ? SystemUiMode.edgeToEdge
            : hiddenChromeUiMode(fullscreen: fullscreen),
      );
      SystemChrome.setSystemUIOverlayStyle(readerOverlayStyle);

      return () => controller.removeStatusListener(onStatus);
    }, [controller, darkIcons, fullscreen]);

    // ── Drive the controller from the visibility notifier ─────────────────────
    useEffect(() {
      void onVisibilityChanged() {
        if (visibility.value) {
          controller.forward();
        } else {
          controller.reverse();
        }
      }

      visibility.addListener(onVisibilityChanged);
      return () => visibility.removeListener(onVisibilityChanged);
    }, [visibility, controller]);

    // Two curves off the ONE controller: slide = tween(200) and
    // fade = tween(150) (the fade is FASTER than the
    // slide), both on FastOutSlowIn (Material standard) rather than a flat
    // easeInOut. The fade uses an Interval covering the first 150/200 = 0.75 of
    // the timeline so it completes in ~150 ms while the bar slides over 200 ms —
    // this quicker fade is what makes the bars feel snappy on the way in.
    final slide = useMemoized(
      () => CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn),
      [controller],
    );
    final fade = useMemoized(
      () => CurvedAnimation(
        parent: controller,
        curve: const Interval(0.0, 0.75, curve: Curves.fastOutSlowIn),
      ),
      [controller],
    );

    // ── Side seekbar positioning ──────────────────────────────────────────────
    //
    // [ChromeExtents.topInset]    = system status-bar inset + measured top-bar
    //                               height (dp). [ChromeExtents.bottomInset] =
    //                               system nav-bar inset + measured bottom-bar
    //                               height (already includes the nav clearance
    //                               baked inside the bottom controls).
    //
    // Adding 8 dp of breathing room keeps the seekbar from kissing the bar edge.
    // When [forceHorizontalSeekbar] is true, the vertical side seekbar is hidden
    // and the horizontal bottom seekbar serves all modes (including webtoon).
    final extents = ref.watch(chromeExtentsNotifierProvider);
    final forceHorizontal =
        ref.watch(forceHorizontalSeekbarProvider).ifNull(false);
    final leftHanded =
        ref.watch(leftHandedVerticalSeekbarProvider).ifNull(false);
    // "Show page number": a subtle "n / m" pill near the bottom, always
    // mounted (outside the animated bars) so it stays visible while reading.
    final showPageNumber = ref.watch(showPageNumberProvider).ifNull(true);
    final pageCount = totalPageCount ?? chapterPages.chapter.pageCount;

    return ValueListenableBuilder<bool>(
      valueListenable: visibility,
      // We still listen to visibility so the Stack rebuilds when it changes
      // (controls IgnorePointer and keeps reactive state in sync).
      builder: (context, visible, _) {
        return Stack(
          children: [
            // ── Custom filter overlays ────────────────────────────────────────
            // Lowest chrome layer: tints only the page beneath. Below the flash
            // (which must stay visible with filters on) and below the bars
            // (which must never get tinted).
            const Positioned.fill(child: ReaderColorOverlays()),

            // ── Flash on page change ──────────────────────────────────────────
            // Chrome-layer leaf under the bars; IgnorePointer inside, so it can
            // never eat taps or touch the frozen viewer engines.
            Positioned.fill(
              child: ReaderFlashOverlay(currentIndex: currentIndex),
            ),

            // ── Page-number indicator ─────────────────────────────────────────
            // Always-mounted leaf gated only by the pref (NOT the chrome
            // animation), so it stays visible while reading. Sits under the
            // bottom bar in the Stack, so the visible menu covers it.
            if (showPageNumber && pageCount > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: _PageNumberIndicator(
                          currentPage: currentIndex + 1,
                          pageCount: pageCount,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Top bar + utils bar ──────────────────────────────────────────
            // SlideTransition from Offset(0, -1) (fully above viewport) → zero.
            // FadeTransition from 0 → 1, driven by the same curved animation.
            // IgnorePointer when dismissed so the hidden bar doesn't eat taps.
            //
            // ReaderUtilsBar rides in the same Column as the top bar so it
            // slides/fades as one rigid unit with it — its own expand/collapse
            // is a separate, local AnimatedSize.
            //
            // MeasureSize now wraps BOTH bars (moved down from ReaderTopBar
            // alone) so chromeExtentsNotifierProvider's topInset covers the
            // utils bar's height too when it's expanded — otherwise the side
            // seekbar's `top` offset would sit above the top bar only and
            // overlap the expanded utils bar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: controller.isDismissed,
                child: FadeTransition(
                  opacity: fade,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(slide),
                    child: MeasureSize(
                      onChange: (size) {
                        // Fires from a post-frame callback; the reader may have
                        // unmounted by then, so never touch ref after dispose.
                        if (!context.mounted) return;
                        final current = ref.read(chromeExtentsNotifierProvider);
                        final next = ChromeExtents(
                          topInset: size.height,
                          bottomInset: current.bottomInset,
                        );
                        ref
                            .read(chromeExtentsNotifierProvider.notifier)
                            .update(next);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReaderTopBar(
                            manga: manga,
                            chapter: chapter,
                            onBack: () => context.pop(),
                          ),
                          // Komikku-style pulldown, shown only where an
                          // auto-scroll/advance engine is actually mounted so
                          // the toggle is never a dead control.
                          if (autoScrollSupported)
                            ReaderUtilsBar(
                              expanded: utilsBarExpanded,
                              readerMode: resolvedReaderMode,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Side seek bar (webtoon) ───────────────────────────────────────
            // Shown when the caller signals vertical mode AND the user has NOT
            // toggled [forceHorizontalSeekbar] on.  The [Positioned] edges are
            // derived from the measured [ChromeExtents] so the seekbar never
            // overlaps the top or bottom chrome bars (Bug A fix).
            //
            // [top]    = e.topInset + 8 dp breathing room.
            // [bottom] = e.bottomInset + 8 dp breathing room.
            //            (bottomInset already includes the nav-bar clearance
            //             that the bottom controls bake in.)
            //
            // Fade only — no slide, to avoid fighting the seek gesture.
            if (showSideSeekBar && !forceHorizontal)
              Positioned(
                right: leftHanded ? null : 6,
                left: leftHanded ? 6 : null,
                top: extents.topInset + 8,
                bottom: extents.bottomInset + 8,
                width: 56,
                // Fade-only (no slide), so at opacity 0 it still hit-tests. The
                // enclosing builder only rebuilds on visibility changes, not on
                // the fade settling — AnimatedBuilder re-evaluates `ignoring` on
                // the final dismissed tick so a tap on this edge column after
                // hiding re-shows the menu instead of scrubbing.
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) => IgnorePointer(
                    ignoring: controller.isDismissed,
                    child: child,
                  ),
                  child: FadeTransition(
                    opacity: fade,
                    child: ReaderSideSeekBar(
                      currentIndex: currentIndex,
                      pageCount:
                          totalPageCount ?? chapterPages.chapter.pageCount,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ),

            // ── Bottom controls ───────────────────────────────────────────────
            // SlideTransition from Offset(0, 1) (fully below viewport) → zero.
            // The nav-inset padding is applied INSIDE the bottom controls,
            // so it slides as one rigid unit with the bar — no stutter.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: controller.isDismissed,
                child: FadeTransition(
                  opacity: fade,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(slide),
                    child: ReaderBottomControls(
                      chapter: chapter,
                      chapterPages: chapterPages,
                      currentIndex: currentIndex,
                      totalPageCount: totalPageCount,
                      useBottomSeekBar: useBottomSeekBar,
                      scrollDirection: scrollDirection,
                      nextPrevChapterPair: nextPrevChapterPair,
                      resolvedReaderMode: resolvedReaderMode,
                      reverseSeekBar: reverseSeekBar,
                      onChanged: onChanged,
                      onOpenSettings: onOpenSettings,
                      onOpenReaderMode: onOpenReaderMode,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Subtle "n / m" pill, styled off the shared reader-nav surface token so it
/// matches the bar capsules.
class _PageNumberIndicator extends StatelessWidget {
  const _PageNumberIndicator({
    required this.currentPage,
    required this.pageCount,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: readerNavSurface(cs),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$currentPage / $pageCount',
        style: context.textTheme.labelMedium?.copyWith(color: cs.onSurface),
      ),
    );
  }
}
