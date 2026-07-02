// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_sizes.dart';
import '../../../../../../routes/router_config.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_batch/chapter_batch_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../widgets/chapter_actions/single_chapter_action_icon.dart';
import '../../controller/reader_controller.dart';
import '../brand_page_seekbar.dart';
import '../reader_mode/infinity_continuous/measure_size.dart';
import 'chrome_extents.dart';

/// The reader's bottom chrome controls, extracted from [ReaderWrapper]'s
/// [Scaffold.bottomSheet] slot.
///
/// - **Paged / horizontal mode** ([useBottomSeekBar] true): shows the
///   horizontal [BrandPageSeekBar] row (with prev/next chapter buttons) plus
///   the action row (bookmark · reader-mode · settings gear).
/// - **Webtoon / vertical mode** ([useBottomSeekBar] false): shows ONLY the
///   action row — the horizontal seek row is dropped, exactly as the old
///   bottomSheet did when `useBottomSeekBar` was false.
///
/// Visual output is byte-identical to the old bottomSheet content.
class MihonBottomControls extends ConsumerWidget {
  const MihonBottomControls({
    super.key,
    required this.chapter,
    required this.chapterPages,
    required this.currentIndex,
    required this.totalPageCount,
    required this.useBottomSeekBar,
    required this.scrollDirection,
    required this.nextPrevChapterPair,
    required this.invertTap,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onOpenReaderMode,
  });

  final ChapterDto chapter;
  final ChapterPagesDto chapterPages;
  final int currentIndex;

  /// For infinity-scroll mode; null means use [chapterPages.chapter.pageCount].
  final int? totalPageCount;

  /// True when horizontal seek bar should be shown (paged / landscape modes).
  final bool useBottomSeekBar;
  final Axis scrollDirection;
  final ({ChapterDto? first, ChapterDto? second})? nextPrevChapterPair;

  /// RTL inversion flag for [BrandPageSeekBar].
  final bool invertTap;

  final ValueChanged<int> onChanged;

  /// Callback for the settings gear button (opens the end drawer).
  final VoidCallback onOpenSettings;

  /// Callback for the reader-mode icon button.
  final VoidCallback onOpenReaderMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterId = chapter.id;
    final fallbackIsBookmarked = chapter.isBookmarked;

    // Nav-bar inset (viewPadding — MediaQuery.padding reads 0 under edge-to-edge).
    // Applied inside the Card below so its surface fills behind the nav bar.
    final view = View.of(context);
    final systemBottomInset = view.viewPadding.bottom / view.devicePixelRatio;

    // Report the bar's full resting height (nav clearance is baked into the Card)
    // so the side seekbar anchors to its visual bottom.
    return MeasureSize(
      onChange: (size) {
        final current = ref.read(chromeExtentsNotifierProvider);
        final next = ChromeExtents(
          topInset: current.topInset,
          bottomInset: size.height,
        );
        ref.read(chromeExtentsNotifierProvider.notifier).update(next);
      },
      child: ExcludeFocus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Horizontal seek row — paged mode only.
            if (useBottomSeekBar) ...[
              Row(
                children: [
                  Card(
                    shape: const CircleBorder(),
                    elevation: 0,
                    color: readerNavSurface(context.theme.colorScheme),
                    child: IconButton(
                      onPressed: nextPrevChapterPair?.second != null
                          ? () => ReaderRoute(
                                mangaId:
                                    nextPrevChapterPair!.second!.mangaId,
                                chapterId: nextPrevChapterPair!.second!.id,
                                toPrev: true,
                                transVertical:
                                    scrollDirection != Axis.vertical,
                              ).pushReplacement(context)
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                  ),
                  Expanded(
                    child: BrandPageSeekBar(
                      currentValue: currentIndex,
                      maxValue:
                          totalPageCount ?? chapterPages.chapter.pageCount,
                      onChanged: onChanged,
                      inverted: invertTap,
                      capsuleColor: readerNavSurface(context.theme.colorScheme),
                    ),
                  ),
                  Card(
                    shape: const CircleBorder(),
                    elevation: 0,
                    color: readerNavSurface(context.theme.colorScheme),
                    child: IconButton(
                      onPressed: nextPrevChapterPair?.first != null
                          ? () => ReaderRoute(
                                mangaId:
                                    nextPrevChapterPair!.first!.mangaId,
                                chapterId: nextPrevChapterPair!.first!.id,
                                transVertical:
                                    scrollDirection != Axis.vertical,
                              ).pushReplacement(context)
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ),
                ],
              ),
              const Gap(8),
            ],
            // Action row — always shown.
            Card(
              // Shared chrome surface; fills behind the nav bar via the padding below.
              color: readerNavSurface(context.theme.colorScheme),
              elevation: 0,
              shape: const RoundedRectangleBorder(),
              margin: EdgeInsets.zero,
              child: Padding(
                // Horizontal + nav-bar inset only — flat and compact.
                padding: KEdgeInsets.h16.size +
                    EdgeInsets.only(bottom: systemBottomInset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ReaderBookmarkButton(
                      chapterId: chapterId,
                      fallbackIsBookmarked: fallbackIsBookmarked,
                    ),
                    IconButton(
                      icon: const Icon(Icons.app_settings_alt_outlined),
                      onPressed: onOpenReaderMode,
                    ),
                    IconButton(
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reader's bookmark toggle. Mirrors the private [_ReaderBookmarkButton]
/// that previously lived in [reader_wrapper.dart].
///
/// Watches the chapter's bookmark state directly so the icon flips the moment
/// a toggle lands — the surrounding controls are always mounted (no longer in
/// a persistent bottomSheet), but the pattern is retained for correctness.
class _ReaderBookmarkButton extends ConsumerWidget {
  const _ReaderBookmarkButton({
    required this.chapterId,
    required this.fallbackIsBookmarked,
  });

  final int chapterId;
  final bool fallbackIsBookmarked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBookmarked = ref.watch(
          chapterProvider(chapterId: chapterId)
              .select((c) => c.valueOrNull?.isBookmarked),
        ) ??
        fallbackIsBookmarked;
    return SingleChapterActionIcon(
      icon: isBookmarked
          ? Icons.bookmark_rounded
          : Icons.bookmark_outline_rounded,
      chapterId: chapterId,
      change: ChapterChange(isBookmarked: !isBookmarked),
      refresh: () => ref.refresh(chapterProvider(chapterId: chapterId).future),
    );
  }
}
