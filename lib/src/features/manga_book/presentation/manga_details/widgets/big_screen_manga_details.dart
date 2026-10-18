// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../../offline/presentation/offline_settings_format.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import '../controller/chapter_list_entry.dart';
import '../controller/manga_details_controller.dart';
import 'add_to_library_category.dart';
import 'chapter_context_menu.dart';
import 'chapter_list_tile.dart';
import 'manga_chapter_organizer.dart';
import 'manga_description.dart';
import 'missing_chapters_tile.dart';
import 'recommends_row.dart';
import 'series_info_column.dart';

/// Width at which the chapter column switches to one-line desktop rows.
const _wideChapterColumn = 488.0;

/// Width below which the column returns to two-line rows. The gap between the
/// two thresholds keeps a column sitting on the breakpoint from flapping.
const _narrowChapterColumn = 472.0;

/// Row style for a column [width], keeping [wide] while inside the band.
bool _wideRowsForWidth(bool? wide, double width) {
  if (width >= _wideChapterColumn) return true;
  if (width < _narrowChapterColumn) return false;
  return wide ?? false;
}

/// Re-anchors the list on the chapter that was at the top when the row style
/// changes. The two rows have different heights, so the pixel offset no longer
/// points at the same chapter.
int? _topChapterIndex(ItemPositionsListener positions) {
  final visible = positions.itemPositions.value.where(
    (position) => position.itemTrailingEdge > 0,
  );
  if (visible.isEmpty) return null;
  return visible
      .map((position) => position.index)
      .reduce((a, b) => a < b ? a : b);
}

class BigScreenMangaDetails extends HookConsumerWidget {
  const BigScreenMangaDetails({
    super.key,
    required this.chapterList,
    required this.expansion,
    required this.manga,
    required this.mangaId,
    required this.selectedChapters,
    required this.onListRefresh,
    required this.onRefresh,
    required this.onDescriptionRefresh,
  });
  final SeriesInfoExpansion expansion;
  final MangaDto manga;
  final int mangaId;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<MangaChapterListEntry>?> chapterList;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = context.isWideDesktop;
    final selection = useValueListenable(selectedChapters);
    final selecting = selection.isNotEmpty;
    final anchor = useState<int?>(null);
    // Survives column rebuilds; the first width seen picks the initial style.
    final wideColumn = useRef<bool?>(null);
    // Row index to land on when the list remounts for a row-style switch.
    final restoreIndex = useRef<int?>(null);
    final itemPositionsListener = useMemoized(ItemPositionsListener.create);
    final filterButtonKey = useMemoized(GlobalKey.new);
    final moreButtonKey = useMemoized(GlobalKey.new);
    final filterFocus = useMemoized(FocusNode.new);
    useEffect(() => filterFocus.dispose, [filterFocus]);

    final rawChapters = ref.watch(mangaChapterListProvider(mangaId: mangaId));
    final totalCount = rawChapters.value?.length ?? 0;
    final unreadCount =
        rawChapters.value?.where((c) => !c.isRead.ifNull()).length ?? 0;
    final onDeviceBytes =
        ref.watch(offlineMangaBytesProvider(mangaId: mangaId)).value ?? 0;
    final filterCount =
        (ref.watch(mangaChapterFilterUnreadProvider) != null ? 1 : 0) +
        (ref.watch(mangaChapterFilterDownloadedProvider) != null ? 1 : 0) +
        (ref.watch(mangaChapterFilterBookmarkedProvider) != null ? 1 : 0) +
        ((ref
                    .watch(mangaPreferredScanlatorsProvider(mangaId: mangaId))
                    .isNotEmpty &&
                !ref.watch(
                  mangaShowAllScanlatorVersionsProvider(mangaId: mangaId),
                ))
            ? 1
            : 0);
    final currentId = ref
        .watch(firstUnreadInFilteredChapterListProvider(mangaId: mangaId))
        ?.id;

    // A cleared selection drops its range anchor too, so a later shift-click
    // never extends from a stale row (Esc is handled by the series page).
    final wasSelecting = usePrevious(selecting);
    useEffect(() {
      if (!selecting && wasSelecting == true) anchor.value = null;
      return null;
    }, [selecting]);

    void toggleSelect(ChapterDto val) {
      if ((val.id).isNull) return;
      selectedChapters.value = selectedChapters.value.toggleKey(val.id, val);
    }

    Future<void> barRefresh(bool online) async {
      selectedChapters.value = {};
      await onListRefresh(online);
    }

    Future<void> openMenu(
      RelativeRect position,
      ChapterDto chapter,
      List<ChapterDto> ordered,
      List<ChapterDto> bulk,
      void Function() refocus,
    ) => showChapterContextMenu(
      context: context,
      ref: ref,
      position: position,
      manga: manga,
      chapter: chapter,
      selectedChapters: selectedChapters,
      selectionAnchor: anchor,
      orderedChapters: ordered,
      bulkChapters: bulk,
      refresh: () => onListRefresh(false),
      refocus: refocus,
    );

    Future<void> openFilterPanel() async {
      final box =
          filterButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      await showMenu<void>(
        context: context,
        position: menuAnchorForRect(
          context,
          Rect.fromLTWH(rect.right - 300, rect.bottom + 6, 0, 0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        items: [
          _FilterPanelEntry(
            panelWidth: 300,
            panelHeight: 420,
            child: MangaChapterOrganizer(mangaId: mangaId),
          ),
        ],
        popUpAnimationStyle: context.motionStyle,
      );
      if (context.mounted) filterFocus.requestFocus();
    }

    final chapterEntries = chapterList.value;
    final chapterCount =
        chapterEntries?.whereType<MangaChapterEntry>().length ?? 0;
    return RefreshIndicator(
      onRefresh: () => onRefresh(true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: desktop ? 55 : 1,
            child: SeriesInfoColumn(
              key: ValueKey(mangaId),
              expansion: expansion,
              builder: (expansion) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MangaDescription(
                    expansion: expansion,
                    manga: manga,
                    removeMangaFromLibrary: (() =>
                        removeMangaFromLibraryAndPurge(
                          ProviderScope.containerOf(context, listen: false),
                          mangaId,
                        )),
                    addMangaToLibrary: (() =>
                        addMangaToLibraryWithCategory(ref, context, manga)),
                    refresh: () => onDescriptionRefresh(false),
                  ),
                  if (manga.title.isNotBlank)
                    RecommendsRow(mangaId: mangaId, mangaTitle: manga.title),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 0),
          Expanded(
            flex: desktop ? 45 : 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // One-line rows follow the chapter column's own width, so a
                // tablet split still gets them when the column has room.
                final previousWide = wideColumn.value;
                final wide = _wideRowsForWidth(
                  previousWide,
                  constraints.maxWidth,
                );
                if (previousWide != null && previousWide != wide) {
                  // The list remounts below at the new row height, so hand it
                  // the chapter that was at the top instead of a pixel offset.
                  restoreIndex.value = _topChapterIndex(itemPositionsListener);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => restoreIndex.value = null,
                  );
                }
                wideColumn.value = wide;
                return chapterList.showUiWhenData(context, (data) {
                  if (data.isNotBlank) {
                    final ordered = [
                      for (final e in chapterEntries!)
                        if (e is MangaChapterEntry) e.chapter,
                    ];
                    final orderedIds = [for (final c in ordered) c.id];
                    final bulk =
                        ref
                            .watch(
                              mangaChapterListForBulkActionsProvider(
                                mangaId: mangaId,
                              ),
                            )
                            .value ??
                        ordered;

                    void selectRange(int fromId, int toId) {
                      final from = orderedIds.indexOf(fromId);
                      final to = orderedIds.indexOf(toId);
                      if (from < 0 || to < 0) return;
                      final lo = from < to ? from : to;
                      final hi = from < to ? to : from;
                      selectedChapters.value = {
                        for (var i = lo; i <= hi; i++)
                          ordered[i].id: ordered[i],
                      };
                    }

                    void onRowTap(ChapterDto chapter, bool shift) {
                      if (!selecting && !shift) {
                        ReaderRoute(
                          mangaId: manga.id,
                          chapterId: chapter.id,
                          showReaderLayoutAnimation: true,
                        ).push(context);
                        return;
                      }
                      final anchorId = anchor.value;
                      if (shift && anchorId != null && anchorId != chapter.id) {
                        selectRange(anchorId, chapter.id);
                        return;
                      }
                      toggleSelect(chapter);
                      anchor.value = chapter.id;
                    }

                    return Column(
                      children: [
                        selecting
                            ? _ChapterSelectionHeader(
                                selected: selection.values.toList(),
                                ordered: ordered,
                                bulk: bulk,
                                anchorId: anchor.value,
                                desktop: wide,
                                seriesUrl: manga.realUrl,
                                moreButtonKey: moreButtonKey,
                                onClear: () {
                                  selectedChapters.value = {};
                                  anchor.value = null;
                                },
                                onSelectAll: () => selectedChapters.value = {
                                  for (final c in ordered) c.id: c,
                                },
                                refresh: barRefresh,
                                onSelect: (next, anchorId) {
                                  selectedChapters.value = next;
                                  anchor.value = anchorId;
                                },
                              )
                            : _ChapterHeader(
                                totalCount: totalCount == 0
                                    ? chapterCount
                                    : totalCount,
                                unreadCount: unreadCount,
                                onDeviceBytes: onDeviceBytes,
                                filterCount: filterCount,
                                desktop: wide,
                                filterButtonKey: filterButtonKey,
                                filterFocus: filterFocus,
                                onRefresh: () => onRefresh(true),
                                onFilter: openFilterPanel,
                              ),
                        Expanded(
                          child: ScrollablePositionedList.builder(
                            key: ValueKey(wide),
                            initialScrollIndex: restoreIndex.value ?? 0,
                            itemPositionsListener: itemPositionsListener,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              if (chapterEntries.length == index) {
                                return wide
                                    ? const SizedBox(height: 16)
                                    : const ListTile();
                              }
                              final entry = chapterEntries[index];
                              return switch (entry) {
                                MangaChapterEntry() => ChapterListTile(
                                  key: ValueKey('${entry.chapter.id}'),
                                  manga: manga,
                                  chapter: entry.chapter,
                                  updateData: () => onListRefresh(false),
                                  isSelected: selection.containsKey(
                                    entry.chapter.id,
                                  ),
                                  canTapSelect: selecting,
                                  toggleSelect: toggleSelect,
                                  desktop: wide,
                                  selectionMode: selecting,
                                  isCurrent: entry.chapter.id == currentId,
                                  onRowTap: (shift) =>
                                      onRowTap(entry.chapter, shift),
                                  onSecondaryTapAt: (pos) => openMenu(
                                    menuAnchorForPoint(context, pos),
                                    entry.chapter,
                                    ordered,
                                    bulk,
                                    () {},
                                  ),
                                  onOpenMenu: (rect, refocus) => openMenu(
                                    rect,
                                    entry.chapter,
                                    ordered,
                                    bulk,
                                    refocus,
                                  ),
                                ),
                                MissingChaptersEntry() =>
                                  MissingChaptersListTile(
                                    key: ValueKey('missing-${entry.id}'),
                                    count: entry.count,
                                  ),
                              };
                            },
                            itemCount: chapterEntries.length + 1,
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Emoticons(
                      title: context.l10n.noChaptersFound,
                      button: TextButton(
                        onPressed: () => onListRefresh(true),
                        child: Text(context.l10n.refresh),
                      ),
                    );
                  }
                }, refresh: () => onRefresh(false));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.totalCount,
    required this.unreadCount,
    required this.onDeviceBytes,
    required this.filterCount,
    required this.desktop,
    required this.filterButtonKey,
    required this.filterFocus,
    required this.onRefresh,
    required this.onFilter,
  });
  final int totalCount;
  final int unreadCount;
  final int onDeviceBytes;
  final int filterCount;
  final bool desktop;
  final GlobalKey filterButtonKey;
  final FocusNode filterFocus;
  final VoidCallback onRefresh;
  final VoidCallback onFilter;
  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final subline = StringBuffer(context.l10n.unreadCount(unreadCount));
    if (onDeviceBytes > 0) {
      subline.write(
        ' · ${context.l10n.onDeviceSize(formatBytes(onDeviceBytes))}',
      );
    }
    if (filterCount > 0) {
      subline.write(' · ${context.l10n.filtered}');
    }
    Widget filterIcon = const Icon(Icons.filter_list_rounded);
    if (filterCount > 0) {
      filterIcon = Badge.count(
        count: filterCount,
        backgroundColor: cs.primary,
        textColor: cs.onPrimary,
        child: filterIcon,
      );
    }
    final Widget filterButton = desktop
        ? OutlinedButton.icon(
            key: filterButtonKey,
            focusNode: filterFocus,
            onPressed: onFilter,
            icon: filterIcon,
            label: Text(context.l10n.filter),
            style: filterCount > 0
                ? OutlinedButton.styleFrom(side: BorderSide(color: cs.primary))
                : null,
          )
        : Container(
            decoration: filterCount > 0
                ? BoxDecoration(
                    border: Border.all(color: cs.primary),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: IconButton(
              key: filterButtonKey,
              focusNode: filterFocus,
              tooltip: context.l10n.filter,
              onPressed: onFilter,
              icon: filterIcon,
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.noOfChapters(totalCount),
                  style: context.textTheme.titleMedium,
                ),
                Text(
                  subline.toString(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (desktop)
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(context.l10n.refresh),
            )
          else
            IconButton(
              tooltip: context.l10n.refresh,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 4),
          filterButton,
        ],
      ),
    );
  }
}

class _HeaderAction {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ChapterSelectionHeader extends ConsumerWidget {
  const _ChapterSelectionHeader({
    required this.selected,
    required this.ordered,
    required this.bulk,
    required this.anchorId,
    required this.desktop,
    required this.seriesUrl,
    required this.moreButtonKey,
    required this.onClear,
    required this.onSelectAll,
    required this.refresh,
    required this.onSelect,
  });
  final List<ChapterDto> selected;
  final List<ChapterDto> ordered;
  final List<ChapterDto> bulk;
  final int? anchorId;
  final bool desktop;
  final String? seriesUrl;
  final GlobalKey moreButtonKey;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final AsyncValueSetter<bool> refresh;
  final void Function(Map<int, ChapterDto> next, int anchorId) onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final allRead =
        selected.isNotEmpty && selected.every((c) => c.isRead.ifNull());
    final allBookmarked =
        selected.isNotEmpty && selected.every((c) => c.isBookmarked.ifNull());
    final anchor =
        selected.where((c) => c.id == anchorId).firstOrNull ?? selected.last;

    List<_HeaderAction> actions() => [
      _HeaderAction(
        icon: allRead ? Icons.remove_done_rounded : Icons.done_all_rounded,
        label: allRead ? context.l10n.markAsUnread : context.l10n.markAsRead,
        onTap: () => markChaptersRead(
          context: context,
          ref: ref,
          chapters: selected,
          isRead: !allRead,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: Icons.bookmark_rounded,
        label: allBookmarked
            ? context.l10n.removeBookmark
            : context.l10n.bookmark,
        onTap: () => setChaptersBookmark(
          ref: ref,
          chapters: selected,
          isBookmarked: !allBookmarked,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: Icons.save_alt_rounded,
        label: context.l10n.keepOffline,
        onTap: () => keepChaptersOffline(
          context: context,
          ref: ref,
          chapters: selected,
          refresh: refresh,
        ),
      ),
      _HeaderAction(
        icon: Icons.cloud_download_outlined,
        label: context.l10n.download,
        onTap: () => queueServerDownload(
          context: context,
          ref: ref,
          chapterIds: [for (final c in selected) c.id],
          refresh: refresh,
        ),
      ),
    ];

    Future<void> openMore(List<_HeaderAction> overflowed) async {
      final box =
          moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final anchorIndex = ordered.indexWhere((c) => c.id == anchor.id);
      final browserChapter = chapterHasBrowserTarget(anchor, seriesUrl)
          ? anchor
          : selected
                .where((c) => chapterHasBrowserTarget(c, seriesUrl))
                .firstOrNull;
      await showMenu<void>(
        context: context,
        position: menuAnchorForRect(
          context,
          Rect.fromLTWH(rect.left, rect.top, 0, 0),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        items: [
          for (final action in overflowed)
            PopupMenuItem(
              onTap: action.onTap,
              child: ChapterMenuRow(
                icon: action.icon,
                label: action.label,
              ),
            ),
          if (overflowed.isNotEmpty) const PopupMenuDivider(),
          PopupMenuItem(
            enabled: previousChapters(bulk, anchor).isNotEmpty,
            onTap: () => markPreviousAsRead(
              context: context,
              ref: ref,
              bulkList: bulk,
              anchor: anchor,
              refresh: refresh,
            ),
            child: ChapterMenuRow(
              icon: Icons.history_rounded,
              label: context.l10n.markPreviousAsRead,
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: anchorIndex >= 0,
            onTap: () {
              if (anchorIndex < 0) return;
              onSelect({
                ...{for (final c in selected) c.id: c},
                for (final c in ordered.skip(anchorIndex + 1).take(10)) c.id: c,
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: Icons.playlist_add_check_rounded,
              label: context.l10n.selectNext10,
            ),
          ),
          PopupMenuItem(
            enabled: anchorIndex >= 0,
            onTap: () {
              if (anchorIndex < 0) return;
              onSelect({
                ...{for (final c in selected) c.id: c},
                for (final c in ordered.skip(anchorIndex)) c.id: c,
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: Icons.vertical_align_bottom_rounded,
              label: context.l10n.selectBelow,
            ),
          ),
          PopupMenuItem(
            onTap: () => onSelect({
              for (final c in ordered)
                if (!c.isRead.ifNull()) c.id: c,
            }, anchor.id),
            child: ChapterMenuRow(
              icon: Icons.filter_list_rounded,
              label: context.l10n.selectUnread,
            ),
          ),
          PopupMenuItem(
            onTap: () {
              final ids = {for (final c in selected) c.id};
              final first = ordered.indexWhere((c) => ids.contains(c.id));
              final last = ordered.lastIndexWhere((c) => ids.contains(c.id));
              if (first < 0 || last < 0) return;
              onSelect({
                for (var i = first; i <= last; i++) ordered[i].id: ordered[i],
              }, anchor.id);
            },
            child: ChapterMenuRow(
              icon: Icons.swap_vert_rounded,
              label: context.l10n.selectInBetween,
            ),
          ),
          if (browserChapter != null) const PopupMenuDivider(),
          if (browserChapter != null)
            PopupMenuItem(
              onTap: () => openChapterInBrowser(
                context,
                ref,
                browserChapter,
                seriesUrl,
              ),
              child: ChapterMenuRow(
                icon: Icons.public_rounded,
                label: context.l10n.openInBrowser,
              ),
            ),
        ],
        popUpAnimationStyle: context.motionStyle,
      );
    }

    Future<void> deleteSelected() async {
      final deleted = await deleteChaptersFromServerWithConfirm(
        context: context,
        ref: ref,
        chapters: selected,
      );
      if (deleted) await refresh(true);
    }

    Widget moreButton(List<_HeaderAction> overflowed) => desktop
        ? TextButton.icon(
            key: moreButtonKey,
            onPressed: () => openMore(overflowed),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            label: Text(context.l10n.more),
          )
        : IconButton(
            key: moreButtonKey,
            tooltip: context.l10n.more,
            onPressed: () => openMore(overflowed),
            icon: const Icon(Icons.more_horiz_rounded),
          );

    Widget actionButton(_HeaderAction action) => IconButton(
      tooltip: action.label,
      onPressed: action.onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(action.icon),
    );

    return Padding(
      key: const ValueKey('chapterSelectionHeader'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final all = actions();
          const closeWidth = 48.0;
          const selectAllWidth = 48.0;
          const actionWidth = 40.0;
          const moreWidth = 104.0;
          const moreIconWidth = 48.0;
          const deleteFullWidth = 156.0;
          const deleteIconWidth = 40.0;
          final deleteLabelled =
              desktop &&
              constraints.maxWidth >=
                  closeWidth +
                      selectAllWidth +
                      all.length * actionWidth +
                      moreWidth +
                      deleteFullWidth;
          final deleteWidth = desktop
              ? (deleteLabelled ? deleteFullWidth : deleteIconWidth)
              : 48.0;
          final barWidth = desktop ? moreWidth : moreIconWidth;
          final visible =
              ((constraints.maxWidth -
                          (closeWidth +
                              selectAllWidth +
                              barWidth +
                              deleteWidth)) /
                      actionWidth)
                  .floor()
                  .clamp(0, all.length);
          final shown = all.take(visible).toList();
          final overflowed = all.skip(visible).toList();
          return Row(
            children: [
              IconButton(
                tooltip: context.l10n.cancel,
                icon: const Icon(Icons.close_rounded),
                onPressed: onClear,
              ),
              Flexible(
                child: Text(
                  context.l10n.numSelected(selected.length),
                  style: context.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: context.l10n.selectAll,
                icon: const Icon(Icons.select_all_rounded),
                onPressed: onSelectAll,
              ),
              for (final action in shown) actionButton(action),
              moreButton(overflowed),
              if (deleteLabelled)
                TextButton.icon(
                  onPressed: deleteSelected,
                  icon: Icon(Icons.delete_rounded, color: cs.error, size: 20),
                  label: Text('${context.l10n.delete}…'),
                )
              else if (desktop)
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: deleteSelected,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.delete_rounded, color: cs.error),
                )
              else
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: deleteSelected,
                  icon: Icon(Icons.delete_rounded, color: cs.error),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterPanelEntry extends PopupMenuEntry<void> {
  const _FilterPanelEntry({
    required this.panelWidth,
    required this.panelHeight,
    required this.child,
  });
  final double panelWidth;
  final double panelHeight;
  final Widget child;
  @override
  double get height => panelHeight;
  @override
  bool represents(void value) => false;
  @override
  State<StatefulWidget> createState() => _FilterPanelEntryState();
}

class _FilterPanelEntryState extends State<_FilterPanelEntry> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.panelWidth,
      height: widget.panelHeight,
      child: widget.child,
    );
  }
}
