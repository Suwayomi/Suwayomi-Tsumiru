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
import '../../../../../../utils/motion/reduce_motion.dart';
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

/// Keep all chrome bars mounted and animate together; OS bars follow animation status.
class ReaderChrome extends HookConsumerWidget {
  const ReaderChrome({
    super.key,
    required this.manga,
    required this.chapter,
    required this.chapterPages,
    this.readerScanlatorGroup = '',
    required this.currentIndex,
    required this.totalPageCount,
    required this.visibility,
    required this.utilsBarExpanded,
    required this.useBottomSeekBar,
    required this.showSideSeekBar,
    required this.scrollDirection,
    required this.onPreviousChapter,
    required this.onNextChapter,
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
  final String readerScanlatorGroup;
  final int currentIndex;

  /// For infinity-scroll mode; null means use [chapterPages.chapter.pageCount].
  final int? totalPageCount;

  /// Tracks [visibility] without writing it; ReaderWrapper owns visibility.
  final ValueNotifier<bool> visibility;

  /// ReaderWrapper owns this notifier; the top-bar tune button toggles it.
  final ValueNotifier<bool> utilsBarExpanded;

  final bool useBottomSeekBar;

  final bool showSideSeekBar;

  final Axis scrollDirection;

  /// Null when there is no chapter that way; the button renders disabled.
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  final ReaderMode resolvedReaderMode;

  /// Enable only when an auto-scroll/advance engine is mounted.
  final bool autoScrollSupported;
  final bool reverseSeekBar;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenReaderMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seed animation from visibility to avoid a flash on mount.
    final reduceMotion = context.reduceMotion;
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 200),
      initialValue: visibility.value ? 1.0 : 0.0,
    );

    // Android 16 forces edge-to-edge and ignores bar colours; paint surfaces behind the system bars.
    final darkIcons = context.theme.colorScheme.brightness == Brightness.light;
    final readerOverlayStyle = SystemUiOverlayStyle(
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
      statusBarBrightness: darkIcons ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: darkIcons
          ? Brightness.dark
          : Brightness.light,
    );

    // Show OS bars when chrome enters and hide after dismissal; fullscreen off leaves them visible.
    final fullscreen =
        ref.watch(readerFullscreenProvider) ??
        DBKeys.readerFullscreen.initial as bool;
    useEffect(() {
      void onStatus(AnimationStatus status) {
        switch (status) {
          case AnimationStatus.forward:
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            SystemChrome.setSystemUIOverlayStyle(readerOverlayStyle);
          case AnimationStatus.dismissed:
            SystemChrome.setEnabledSystemUIMode(
              hiddenChromeUiMode(fullscreen: fullscreen),
            );
          case AnimationStatus.reverse:
          case AnimationStatus.completed:
            break;
        }
      }

      controller.addStatusListener(onStatus);

      // Apply initial OS-bar state explicitly; status listeners fire only on transitions.
      SystemChrome.setEnabledSystemUIMode(
        visibility.value
            ? SystemUiMode.edgeToEdge
            : hiddenChromeUiMode(fullscreen: fullscreen),
      );
      SystemChrome.setSystemUIOverlayStyle(readerOverlayStyle);

      return () => controller.removeStatusListener(onStatus);
    }, [controller, darkIcons, fullscreen]);

    useEffect(() {
      void onVisibilityChanged() {
        if (reduceMotion) {
          controller.value = visibility.value ? 1 : 0;
          if (visibility.value) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            SystemChrome.setSystemUIOverlayStyle(readerOverlayStyle);
          }
        } else if (visibility.value) {
          controller.forward();
        } else {
          controller.reverse();
        }
      }

      visibility.addListener(onVisibilityChanged);
      return () => visibility.removeListener(onVisibilityChanged);
    }, [visibility, controller, reduceMotion]);

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

    // Measured extents already include navigation clearance; add only the 8dp breathing room.
    final extents = ref.watch(chromeExtentsProvider);
    final forceHorizontal = ref
        .watch(forceHorizontalSeekbarProvider)
        .ifNull(false);
    final leftHanded = ref
        .watch(leftHandedVerticalSeekbarProvider)
        .ifNull(false);
    final showPageNumber = ref.watch(showPageNumberProvider).ifNull(true);
    final pageCount = totalPageCount ?? chapterPages.chapter.pageCount;

    return ValueListenableBuilder<bool>(
      valueListenable: visibility,
      builder: (context, visible, _) {
        return Stack(
          children: [
            // Tint only the page: filters stay below flash and chrome bars.
            const Positioned.fill(child: ReaderColorOverlays()),

            Positioned.fill(
              child: ReaderFlashOverlay(currentIndex: currentIndex),
            ),

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

            // Measure both top and utils bars so the side seek bar clears expanded controls.
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
                        final current = ref.read(chromeExtentsProvider);
                        final next = ChromeExtents(
                          topInset: size.height,
                          bottomInset: current.bottomInset,
                        );
                        ref.read(chromeExtentsProvider.notifier).update(next);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReaderTopBar(
                            onJump: onChanged,
                            pageCount: chapterPages.pages.length,
                            currentPage: currentIndex,
                            manga: manga,
                            chapter: chapter,
                            onBack: () => context.pop(),
                          ),
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

            // Fade the side seek bar without sliding to avoid fighting seek gestures.
            if (showSideSeekBar && !forceHorizontal)
              Positioned(
                right: leftHanded ? null : 6,
                left: leftHanded ? 6 : null,
                top: extents.topInset + 8,
                bottom: extents.bottomInset + 8,
                width: 56,
                // Re-evaluate hit testing on the final fade tick so hidden controls cannot intercept taps.
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
                      onPreviousChapter: onPreviousChapter,
                      onNextChapter: onNextChapter,
                    ),
                  ),
                ),
              ),

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
                      readerScanlatorGroup: readerScanlatorGroup,
                      chapter: chapter,
                      chapterPages: chapterPages,
                      currentIndex: currentIndex,
                      totalPageCount: totalPageCount,
                      useBottomSeekBar: useBottomSeekBar,
                      scrollDirection: scrollDirection,
                      onPreviousChapter: onPreviousChapter,
                      onNextChapter: onNextChapter,
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
