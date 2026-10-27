// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../../offline/presentation/offline_settings_format.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/chapter_list_entry.dart';
import '../controller/manga_details_controller.dart';
import 'add_to_library_category.dart';
import 'chapter_context_menu.dart';
import 'chapter_grid_tile.dart';
import 'chapter_list_mode_toggle.dart';
import 'chapter_list_tile.dart';
import 'chapter_selection_header.dart';
import 'manga_chapter_organizer.dart';
import 'manga_description.dart';
import 'missing_chapters_tile.dart';
import 'recommends_row.dart';
import 'series_info_column.dart';

/// Row-style changes alter heights, so restore by chapter index rather than pixel offset.
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
    required this.onMigrate,
  });
  final SeriesInfoExpansion expansion;
  final MangaDto manga;
  final int mangaId;
  final AsyncValueSetter<bool> onListRefresh;
  final AsyncValueSetter<bool> onDescriptionRefresh;
  final AsyncCallback onMigrate;
  final AsyncValueSetter<bool> onRefresh;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final AsyncValue<List<MangaChapterListEntry>?> chapterList;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listMode = ref.watch(mangaChapterListModeProvider(mangaId: mangaId));
    final desktop = context.windowSizeClass >= WindowSizeClass.expanded;
    final wide = context.windowSizeClass >= WindowSizeClass.large;
    final selection = useValueListenable(selectedChapters);
    final selecting = selection.isNotEmpty;
    final anchor = useState<int?>(null);
    final previousWide = useRef<bool?>(null);
    final restoreIndex = useRef<int?>(null);
    final itemPositionsListener = useMemoized(ItemPositionsListener.create);
    final filterButtonKey = useMemoized(GlobalKey.new);
    final moreButtonKey = useMemoized(GlobalKey.new);
    final filterFocus = useMemoized(FocusNode.new);
    useEffect(() => filterFocus.dispose, [filterFocus]);

    final rawChapters = ref.watch(mangaChapterListProvider(mangaId: mangaId));
    final totalCount = rawChapters.value?.length ?? 0;
    final unreadCount =
        rawChapters.value?.where((c) => !c.user.isRead.ifNull()).length ?? 0;
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

    // Clear the range anchor with selection so a later shift-click cannot reuse a stale row.
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
      seriesUrl: manga.realUrl,
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
    final lastWide = previousWide.value;
    if (lastWide != null && lastWide != wide) {
      restoreIndex.value = _topChapterIndex(itemPositionsListener);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => restoreIndex.value = null,
      );
    }
    previousWide.value = wide;
    return RefreshIndicator(
      onRefresh: () => onRefresh(true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: wide ? 50 : (desktop ? 55 : 1),
            child: SeriesInfoColumn(
              key: ValueKey(mangaId),
              expansion: expansion,
              builder: (expansion) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MangaDescription(
                    expansion: expansion,
                    manga: manga,
                    onMigrate: onMigrate,
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
            flex: wide ? 50 : (desktop ? 45 : 1),
            child: chapterList.showUiWhenData(context, (data) {
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
                    for (var i = lo; i <= hi; i++) ordered[i].id: ordered[i],
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
                        ? ChapterSelectionHeader(
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
                            mangaId: mangaId,
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
                      child: listMode == ChapterListMode.grid
                          ? GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 64,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                  ),
                              itemCount: chapterEntries.length,
                              itemBuilder: (context, index) {
                                final entry = chapterEntries[index];
                                return switch (entry) {
                                  MangaChapterEntry() => ChapterGridTile(
                                    key: ValueKey('${entry.chapter.id}'),
                                    manga: manga,
                                    chapter: entry.chapter,
                                    isSelected: selection.containsKey(
                                      entry.chapter.id,
                                    ),
                                    canTapSelect: selecting,
                                    toggleSelect: (chapter) {
                                      toggleSelect(chapter);
                                      anchor.value = chapter.id;
                                    },
                                    onRowTap: (shift) =>
                                        onRowTap(entry.chapter, shift),
                                    onSecondaryTapAt: (pos) => openMenu(
                                      menuAnchorForPoint(context, pos),
                                      entry.chapter,
                                      ordered,
                                      bulk,
                                      () {},
                                    ),
                                  ),
                                  MissingChaptersEntry() =>
                                    MissingChaptersGridTile(
                                      key: ValueKey('missing-${entry.id}'),
                                      count: entry.count,
                                    ),
                                };
                              },
                            )
                          : ScrollablePositionedList.builder(
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
                            MissingChaptersEntry() => MissingChaptersListTile(
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
            }, refresh: () => onRefresh(false)),
          ),
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.mangaId,
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
  final int mangaId;
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
    Widget filterIcon = Icon(FluentIcons.filter_24_regular, size: desktop ? 20 : 24);
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
          ChapterListModeToggle(mangaId: mangaId),
          const SizedBox(width: 4),
          if (desktop)
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(FluentIcons.arrow_clockwise_24_regular, size: 20),
              label: Text(context.l10n.refresh),
            )
          else
            IconButton(
              tooltip: context.l10n.refresh,
              onPressed: onRefresh,
              icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
            ),
          const SizedBox(width: 4),
          filterButton,
        ],
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
