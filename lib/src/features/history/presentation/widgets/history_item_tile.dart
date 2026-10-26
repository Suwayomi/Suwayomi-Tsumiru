// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/web_route_link.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../domain/history_item.dart';
import '../../domain/history_menu_action.dart';
import 'history_row_menu.dart';

bool isHistoryChapterCompleted(HistoryItemDto item) {
  final isFullyRead = item.user.isRead == true;
  final hasFinishedChapter =
      item.pageCount > 0 && item.user.lastPageRead >= (item.pageCount - 1);
  return isFullyRead || hasFinishedChapter;
}

void ensureHistoryPreferenceProvidersInitialized(WidgetRef ref, int mangaId) {
  ref.read(mangaChapterSortProvider);
  ref.read(mangaChapterSortDirectionProvider);
  ref.read(mangaChapterFilterUnreadProvider);
  ref.read(mangaChapterFilterDownloadedProvider);
  ref.read(mangaChapterFilterBookmarkedProvider);
  ref.read(mangaPreferredScanlatorsProvider(mangaId: mangaId));
}

void navigateHistoryItemToReader(
  BuildContext context,
  WidgetRef ref,
  HistoryItemDto item,
) {
  if (isHistoryChapterCompleted(item)) {
    navigateToNextHistoryChapterAfterLoading(context, ref, item);
  } else {
    ReaderRoute(mangaId: item.mangaId, chapterId: item.id).push(context);
  }
}

Future<void> navigateToNextHistoryChapterAfterLoading(
  BuildContext context,
  WidgetRef ref,
  HistoryItemDto item,
) async {
  final completer = Completer<void>();
  ProviderSubscription? subscription;

  void navigateAndCleanup(int chapterId) {
    if (completer.isCompleted) return;

    if (context.mounted) {
      ReaderRoute(mangaId: item.mangaId, chapterId: chapterId).push(context);
    }
    subscription?.close();
    completer.complete();
  }

  subscription = ref.listenManual(
    mangaChapterListWithFilterProvider(mangaId: item.mangaId),
    (previous, next) {
      if (next is AsyncData<List<dynamic>?>) {
        final nextPrevChapterPair = ref.read(
          getNextAndPreviousChaptersProvider(
            mangaId: item.mangaId,
            chapterId: item.id,
          ),
        );
        navigateAndCleanup(nextPrevChapterPair?.first?.id ?? item.id);
      } else if (next is AsyncError) {
        navigateAndCleanup(item.id);
      }
    },
  );

  ensureHistoryPreferenceProvidersInitialized(ref, item.mangaId);
  await ref
      .read(mangaChapterListProvider(mangaId: item.mangaId).notifier)
      .refresh();

  Future.any([
    completer.future,
    Future.delayed(const Duration(seconds: 10)).then((_) {
      if (!completer.isCompleted) {
        navigateAndCleanup(item.id);
      }
    }),
  ]);
}

class HistoryItemTile extends StatelessWidget {
  const HistoryItemTile({super.key, required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!context.usesDesktopShell) return _PhoneTile(item: item, onTap: onTap);
    return _DesktopTile(item: item, onTap: onTap);
  }
}

class _DesktopTile extends HookConsumerWidget {
  const _DesktopTile({required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final optionsKey = useMemoized(GlobalKey.new);
    final optionsFocus = useFocusNode();
    final optionsFocused = useState(false);
    final inLibrary = item.manga.user.inLibrary;
    final completed = isHistoryChapterCompleted(item);
    final timeString =
        item.readAt != null ? DateFormat.Hm().format(item.readAt!) : '';

    void openMenuAt(Offset position) {
      showHistoryChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        item: item,
        refocus: () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    void openOptions() {
      final box =
          optionsKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      showHistoryChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForRect(
          context,
          box.localToGlobal(Offset.zero) & box.size,
        ),
        item: item,
        refocus: () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    final scheme = context.theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: WebRouteLink(
        // Completed entries load the next chapter dynamically, so they have no fixed link.
        location: completed
            ? null
            : ReaderRoute(mangaId: item.mangaId, chapterId: item.id).location,
        builder: (context, openInNewTab) => GestureDetector(
          onSecondaryTapDown: (details) =>
              openMenuAt(details.globalPosition),
          child: MouseRegion(
            onEnter: (_) => hovered.value = true,
            onExit: (_) => hovered.value = false,
            child: InkWell(
              onTap: () => WebRouteLink.handleTap(
                openInNewTab,
                onTap ?? () => navigateHistoryItemToReader(context, ref, item),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: WebRouteLink(
                        location: MangaRoute(mangaId: item.mangaId).location,
                        enabled: false,
                        builder: (context, openMangaInNewTab) => InkWell(
                          onTap: () => WebRouteLink.handleTap(
                            openMangaInNewTab,
                            () async {
                              await MangaRoute(
                                mangaId: item.mangaId,
                              ).push(context);
                              if (!context.mounted) return;
                              await refreshHistory(ref);
                            },
                          ),
                          child: ServerImage(
                            imageUrl: item.manga.displayCoverUrl,
                            fallbackImageUrl: item.manga.thumbnailUrl,
                            coverVersion: item.manga.coverVersion,
                            fallbackCoverVersion:
                                item.manga.thumbnailUrlLastFetched,
                            size: const Size(48, 68),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.manga.title,
                            style: context.theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: context.theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _ProgressLine(item: item, completed: completed),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        timeString,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              child: !inLibrary && hovered.value
                                  ? IconButton(
                                      tooltip: context.l10n.addToLibrary,
                                      onPressed: () async {
                                        await addHistorySeriesToLibrary(
                                          ref,
                                          context,
                                          item.mangaId,
                                        );
                                        if (!context.mounted) return;
                                        await refreshHistory(ref);
                                      },
                                      icon: Icon(
                                        FluentIcons.heart_24_regular,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                            ),
                            SizedBox(
                              width: 32,
                              child: Visibility(
                                visible:
                                    hovered.value || optionsFocused.value,
                                maintainSize: true,
                                maintainState: true,
                                maintainAnimation: true,
                                child: Focus(
                                  focusNode: optionsFocus,
                                  onFocusChange: (v) =>
                                      optionsFocused.value = v,
                                  child: IconButton(
                                    key: optionsKey,
                                    tooltip: context.l10n.more,
                                    onPressed: openOptions,
                                    icon: Icon(
                                      FluentIcons.more_vertical_24_regular,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.item, required this.completed});

  final HistoryItemDto item;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    if (completed) {
      return Text(
        context.l10n.historyChapterCompleted,
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: scheme.secondary,
        ),
      );
    }
    if (item.user.lastPageRead <= 0 || item.pageCount <= 0) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: item.user.lastPageRead / item.pageCount,
              minHeight: 3,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.l10n.pageOfTotal(item.user.lastPageRead, item.pageCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneMetaLine extends StatelessWidget {
  const _PhoneMetaLine({required this.item});

  final HistoryItemDto item;

  @override
  Widget build(BuildContext context) {
    final completed = isHistoryChapterCompleted(item);
    final timeString =
        item.readAt != null ? DateFormat.Hm().format(item.readAt!) : '';
    return Row(
      children: [
        if (timeString.isNotEmpty) ...[
          Icon(
            FluentIcons.clock_24_regular,
            size: 14,
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            timeString,
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (item.user.lastPageRead > 0 && item.pageCount > 0) ...[
          const SizedBox(width: 8),
          Icon(
            completed
                ? FluentIcons.checkmark_circle_24_filled
                : FluentIcons.bookmark_24_regular,
            size: 14,
            color: completed
                ? context.theme.colorScheme.secondary
                : context.theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            completed
                ? context.l10n.historyChapterCompleted
                : '${item.user.lastPageRead}/${item.pageCount}',
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: completed
                  ? context.theme.colorScheme.secondary
                  : context.theme.colorScheme.primary,
            ),
          ),
        ],
        if (item.scanlator.isNotBlank) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.scanlator!,
              style: context.theme.textTheme.labelSmall?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _PhoneTile extends ConsumerWidget {
  const _PhoneTile({required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: WebRouteLink(
        // Completed entries load the next chapter dynamically, so they have no fixed link.
        location: isHistoryChapterCompleted(item)
            ? null
            : ReaderRoute(mangaId: item.mangaId, chapterId: item.id).location,
        builder: (context, openInNewTab) => InkWell(
          onTap: () => WebRouteLink.handleTap(
            openInNewTab,
            onTap ?? () => navigateHistoryItemToReader(context, ref, item),
          ),
          onLongPress: () => showHistoryActionsSheet(
            context: context,
            ref: ref,
            item: item,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ServerImage(
                    imageUrl: item.manga.displayCoverUrl,
                    fallbackImageUrl: item.manga.thumbnailUrl,
                    coverVersion: item.manga.coverVersion,
                    fallbackCoverVersion: item.manga.thumbnailUrlLastFetched,
                    size: const Size(56, 80),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.manga.title,
                        style: context.theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        style: context.theme.textTheme.bodyMedium?.copyWith(
                          color: context.theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _PhoneMetaLine(item: item),
                    ],
                  ),
                ),
                PopupMenuButton<HistoryMenuAction>(
                  icon: Icon(
                    FluentIcons.more_vertical_24_regular,
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case HistoryMenuAction.viewManga:
                        MangaRoute(mangaId: item.mangaId).push(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => HistoryMenuAction.values
                      .map(
                        (action) => PopupMenuItem(
                          value: action,
                          child: ChapterMenuRow(
                            icon: action.icon,
                            label: action.toLocale(context),
                          ),
                        ),
                      )
                      .toList(),
                  popUpAnimationStyle: context.motionStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
