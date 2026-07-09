// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_sizes.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../routes/router_config.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../offline/presentation/offline_save_button.dart';
import '../../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import '../../../../widgets/download_status_icon.dart';
import '../../../manga_details/controller/manga_details_controller.dart';
import '../brand_page_seekbar.dart';
import '../reader_mode/infinity_continuous/measure_size.dart';
import 'chrome_extents.dart';

/// The reader's bottom chrome controls, extracted from [ReaderWrapper]'s
/// [Scaffold.bottomSheet] slot.
///
/// - **Paged / horizontal mode** ([useBottomSeekBar] true): shows the
///   horizontal [BrandPageSeekBar] row (with prev/next chapter buttons) plus
///   the action row.
/// - **Webtoon / vertical mode** ([useBottomSeekBar] false): shows ONLY the
///   action row.
class ReaderBottomControls extends ConsumerWidget {
  const ReaderBottomControls({
    super.key,
    required this.chapter,
    required this.chapterPages,
    required this.currentIndex,
    required this.totalPageCount,
    required this.useBottomSeekBar,
    required this.scrollDirection,
    required this.nextPrevChapterPair,
    required this.resolvedReaderMode,
    required this.reverseSeekBar,
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
  final ReaderMode resolvedReaderMode;
  final bool reverseSeekBar;

  final ValueChanged<int> onChanged;

  /// Callback for the settings gear button (opens the end drawer).
  final VoidCallback onOpenSettings;

  /// Callback for the reader-mode icon button.
  final VoidCallback onOpenReaderMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = View.of(context);
    final systemBottomInset = view.viewPadding.bottom / view.devicePixelRatio;
    final isPagedMode = _isPagedReaderMode(resolvedReaderMode);
    final pageLayout = ref.watch(pageLayoutKeyProvider) ?? PageLayout.automatic;
    final dualPageSplitPaged = ref.watch(dualPageSplitPagedProvider).ifNull();
    final cropBorders = isPagedMode
        ? ref.watch(cropBordersProvider).ifNull()
        : ref.watch(cropBordersWebtoonProvider).ifNull();

    void toggleCropBorders() {
      if (isPagedMode) {
        ref.read(cropBordersProvider.notifier).update(!cropBorders);
      } else {
        ref.read(cropBordersWebtoonProvider.notifier).update(!cropBorders);
      }
    }

    void togglePageLayout() {
      final next = pageLayout == PageLayout.doublePages
          ? PageLayout.singlePage
          : PageLayout.doublePages;
      ref.read(pageLayoutKeyProvider.notifier).update(next);
    }

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
                                mangaId: nextPrevChapterPair!.second!.mangaId,
                                chapterId: nextPrevChapterPair!.second!.id,
                                toPrev: true,
                                transVertical: scrollDirection == Axis.vertical,
                                openAtEnd: true,
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
                      inverted: reverseSeekBar,
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
                                mangaId: nextPrevChapterPair!.first!.mangaId,
                                chapterId: nextPrevChapterPair!.first!.id,
                                transVertical: scrollDirection == Axis.vertical,
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
              color: readerNavSurface(context.theme.colorScheme),
              elevation: 0,
              shape: const RoundedRectangleBorder(),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: KEdgeInsets.h16.size +
                    EdgeInsets.only(bottom: systemBottomInset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.format_list_numbered_rounded),
                      onPressed: () => _showChapterPicker(
                        context: context,
                        mangaId: chapter.mangaId,
                        currentChapterId: chapter.id,
                        transVertical: scrollDirection == Axis.vertical,
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.readerMode,
                      icon: Icon(_readerModeIcon(resolvedReaderMode)),
                      onPressed: onOpenReaderMode,
                    ),
                    IconButton(
                      tooltip: context.l10n.cropBorders,
                      icon: Icon(
                        cropBorders
                            ? Icons.crop_rounded
                            : Icons.crop_free_rounded,
                      ),
                      onPressed: toggleCropBorders,
                    ),
                    if (isPagedMode && !dualPageSplitPaged)
                      IconButton(
                        tooltip: context.l10n.pageLayout,
                        icon: Icon(_pageLayoutIcon(pageLayout)),
                        onPressed: togglePageLayout,
                      ),
                    IconButton(
                      tooltip: context.l10n.settings,
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

bool _isPagedReaderMode(ReaderMode mode) => switch (mode) {
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.singleVertical ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        true,
      ReaderMode.defaultReader ||
      ReaderMode.continuousVertical ||
      ReaderMode.webtoon =>
        false,
    };

IconData _readerModeIcon(ReaderMode mode) => switch (mode) {
      ReaderMode.webtoon ||
      ReaderMode.continuousVertical =>
        Icons.public_rounded,
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.singleVertical ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        Icons.menu_book_rounded,
      ReaderMode.defaultReader => Icons.auto_stories_rounded,
    };

IconData _pageLayoutIcon(PageLayout pageLayout) => switch (pageLayout) {
      PageLayout.singlePage => Icons.menu_book_rounded,
      PageLayout.doublePages => Icons.chrome_reader_mode_rounded,
      PageLayout.automatic => Icons.auto_stories_rounded,
    };

Future<void> _showChapterPicker({
  required BuildContext context,
  required int mangaId,
  required int currentChapterId,
  required bool transVertical,
}) {
  final readerContext = context;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.42,
        minChildSize: 0.22,
        maxChildSize: 0.82,
        builder: (context, scrollController) {
          return Material(
            color: context.theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final chapters = ref.watch(
                  mangaChapterListWithFilterProvider(mangaId: mangaId),
                );
                return chapters.showUiWhenData(
                  context,
                  (items) => _ReaderChapterSheet(
                    chapters: items ?? const [],
                    currentChapterId: currentChapterId,
                    mangaId: mangaId,
                    readerContext: readerContext,
                    scrollController: scrollController,
                    transVertical: transVertical,
                    refreshChapters: () async {
                      final reload = ref.refresh(
                        mangaChapterListProvider(mangaId: mangaId).future,
                      );
                      await reload;
                    },
                  ),
                );
              },
            ),
          );
        },
      );
    },
  );
}

class _ReaderChapterSheet extends StatelessWidget {
  const _ReaderChapterSheet({
    required this.chapters,
    required this.currentChapterId,
    required this.mangaId,
    required this.readerContext,
    required this.scrollController,
    required this.transVertical,
    required this.refreshChapters,
  });

  final List<ChapterDto> chapters;
  final int currentChapterId;
  final int mangaId;
  final BuildContext readerContext;
  final ScrollController scrollController;
  final bool transVertical;
  final Future<void> Function() refreshChapters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 32,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.l10n.noOfChapters(chapters.length),
              style: context.textTheme.titleMedium,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
            ),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              final isCurrent = chapter.id == currentChapterId;
              final lastPageRead =
                  chapter.lastPageRead.getValueOnNullOrNegative();
              return ListTile(
                dense: true,
                visualDensity:
                    const VisualDensity(horizontal: -1, vertical: -3),
                minLeadingWidth: 24,
                minVerticalPadding: 0,
                contentPadding: const EdgeInsets.only(left: 16, right: 8),
                selected: isCurrent,
                selectedTileColor:
                    colorScheme.primaryContainer.withValues(alpha: 0.55),
                selectedColor: colorScheme.onPrimaryContainer,
                leading: Icon(
                  chapter.isRead.ifNull()
                      ? Icons.check_circle_outline_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                ),
                title: Text(
                  chapter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: lastPageRead > 0
                    ? Text(
                        context.l10n.page(lastPageRead + 1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall,
                      )
                    : null,
                trailing: IconButtonTheme(
                  data: IconButtonThemeData(
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(
                        Size.square(36),
                      ),
                      fixedSize: const WidgetStatePropertyAll(Size.square(36)),
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  child: SizedBox(
                    width: 80,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OfflineSaveButton(chapterId: chapter.id),
                        DownloadStatusIcon(
                          updateData: refreshChapters,
                          chapter: chapter,
                          mangaId: mangaId,
                          isDownloaded: chapter.isDownloaded.ifNull(),
                        ),
                      ],
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (isCurrent) return;
                  if (!readerContext.mounted) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!readerContext.mounted) return;
                    ReaderRoute(
                      mangaId: mangaId,
                      chapterId: chapter.id,
                      showReaderLayoutAnimation: true,
                      transVertical: transVertical,
                    ).pushReplacement(readerContext);
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
