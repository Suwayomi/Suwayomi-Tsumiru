// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
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

class HistoryItemTile extends ConsumerWidget {
  const HistoryItemTile({super.key, required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  bool _isChapterCompleted() {
    final isFullyRead = item.user.isRead == true;
    final hasFinishedChapter =
        item.pageCount > 0 && item.user.lastPageRead >= (item.pageCount - 1);
    return isFullyRead || hasFinishedChapter;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readDate = item.readAt;
    final timeString = readDate != null ? DateFormat.Hm().format(readDate) : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: WebRouteLink(
        // Completed entries load the next chapter dynamically, so they have no fixed link.
        location: _isChapterCompleted()
            ? null
            : ReaderRoute(mangaId: item.mangaId, chapterId: item.id).location,
        builder: (context, openInNewTab) => InkWell(
          onTap: () => WebRouteLink.handleTap(
            openInNewTab,
            onTap ?? () => _navigateToReader(context, ref),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ServerImage(
                    imageUrl: item.manga.thumbnailUrl ?? "",
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
                      Row(
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
                              style: context.theme.textTheme.labelSmall
                                  ?.copyWith(
                                    color: context
                                        .theme
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (item.user.lastPageRead > 0 &&
                              item.pageCount > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              _isChapterCompleted()
                                  ? FluentIcons.checkmark_circle_24_filled
                                  : FluentIcons.bookmark_24_regular,
                              size: 14,
                              color: _isChapterCompleted()
                                  ? context.theme.colorScheme.secondary
                                  : context.theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isChapterCompleted()
                                  ? 'Completed'
                                  : '${item.user.lastPageRead}/${item.pageCount}',
                              style: context.theme.textTheme.labelSmall
                                  ?.copyWith(
                                    color: _isChapterCompleted()
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
                                style: context.theme.textTheme.labelSmall
                                    ?.copyWith(
                                      color: context
                                          .theme
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                        _navigateToManga(context);
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

  void _ensurePreferenceProvidersInitialized(WidgetRef ref) {
    ref.read(mangaChapterSortProvider);
    ref.read(mangaChapterSortDirectionProvider);
    ref.read(mangaChapterFilterUnreadProvider);
    ref.read(mangaChapterFilterDownloadedProvider);
    ref.read(mangaChapterFilterBookmarkedProvider);
    ref.read(mangaPreferredScanlatorsProvider(mangaId: item.mangaId));
  }

  void _navigateToReader(BuildContext context, WidgetRef ref) {
    if (_isChapterCompleted()) {
      _navigateToNextChapterAfterLoading(context, ref);
    } else {
      ReaderRoute(mangaId: item.mangaId, chapterId: item.id).push(context);
    }
  }

  Future<void> _navigateToNextChapterAfterLoading(
    BuildContext context,
    WidgetRef ref,
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

    _ensurePreferenceProvidersInitialized(ref);
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

  void _navigateToManga(BuildContext context) {
    MangaRoute(mangaId: item.mangaId).push(context);
  }
}
