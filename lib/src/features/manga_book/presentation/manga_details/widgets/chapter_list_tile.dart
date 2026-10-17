// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../offline/presentation/offline_save_button.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import '../../../widgets/download_status_icon.dart';
import '../controller/manga_details_controller.dart';
import 'chapter_context_menu.dart';

/// Opens the chapter menu anchored at [position], then runs [refocus] (the
/// row guards it with its own mounted state).
typedef ChapterMenuOpener =
    void Function(RelativeRect position, void Function() refocus);

class ChapterListTile extends HookConsumerWidget {
  const ChapterListTile({
    super.key,
    required this.manga,
    required this.chapter,
    required this.updateData,
    required this.toggleSelect,
    this.canTapSelect = false,
    this.isSelected = false,
    this.desktop = false,
    this.selectionMode = false,
    this.isCurrent = false,
    this.onRowTap,
    this.onSecondaryTapAt,
    this.onOpenMenu,
  });
  final MangaDto manga;
  final ChapterDto chapter;
  final AsyncCallback updateData;
  final ValueChanged<ChapterDto> toggleSelect;
  final bool canTapSelect;
  final bool isSelected;

  /// Desktop (>= 1200) one-line column layout with hover actions.
  final bool desktop;

  /// Whether any selection is active (shows checkboxes on desktop).
  final bool selectionMode;

  /// The chapter Resume would open: accent bar, tint and progress line.
  final bool isCurrent;

  /// Desktop tap handler; [shift] is true for a Shift-click range extend.
  final ValueChanged<bool>? onRowTap;

  /// Desktop right-click handler with the global tap position.
  final ValueChanged<Offset>? onSecondaryTapAt;

  /// Desktop ⋮ handler with the menu anchor, computed from the button, plus
  /// a focus-return callback the row guards with its own mounted state.
  final ChapterMenuOpener? onOpenMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!desktop) return _phoneTile(context, ref);
    return _desktopRow(context, ref);
  }

  Widget _phoneTile(BuildContext context, WidgetRef ref) {
    final showChapterNumber =
        ref.watch(mangaChapterDisplayModeProvider) ==
        ChapterDisplay.chapterNumber;
    final scanlator = chapter.scanlator.isNotBlank
        ? chapter.scanlator!
        : context.l10n.unknownScanlator;
    // Mihon parity: a read chapter is drawn at 38% of the normal colour.
    final readColor = context.theme.colorScheme.onSurface.withValues(
      alpha: 0.38,
    );
    return GestureDetector(
      key: Key("manga-${manga.id}-chapter-${chapter.id}"),
      onSecondaryTap: () => toggleSelect(chapter),
      child: ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chapter.isBookmarked.ifNull()) ...[
              Icon(
                Icons.bookmark_rounded,
                color: chapter.isRead.ifNull() ? readColor : context.iconColor,
                size: 20,
              ),
              const Gap(4),
            ],
            Expanded(
              child: Text(
                showChapterNumber
                    ? context.l10n.chapterNumber(chapter.formattedChapterNumber)
                    : chapter.name,
                style: TextStyle(
                  color: chapter.isRead.ifNull() ? readColor : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              int.tryParse(chapter.uploadDate).toDaysAgo(context),
              style: TextStyle(
                color: chapter.isRead.ifNull() ? readColor : null,
              ),
            ),
            if (!chapter.isRead.ifNull() &&
                (chapter.lastPageRead).getValueOnNullOrNegative() != 0)
              Text(
                " • ${context.l10n.page(chapter.lastPageRead.getValueOnNullOrNegative() + 1)}",
                style: TextStyle(
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            Expanded(
              child: Text(
                " • $scanlator",
                style: TextStyle(
                  color: chapter.isRead.ifNull() ? readColor : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OfflineSaveButton(chapterId: chapter.id),
            // Local source: the files are already on the server, so there is
            // nothing to download there (Komikku parity).
            if (!manga.isLocalSource)
              DownloadStatusIcon(
                updateData: updateData,
                chapter: chapter,
                mangaId: manga.id,
                isDownloaded: chapter.isDownloaded.ifNull(),
              ),
          ],
        ),
        selectedColor: context.theme.colorScheme.onSurface,
        selectedTileColor: context.theme.colorScheme.secondaryContainer,
        selected: isSelected,
        onTap: canTapSelect
            ? () => toggleSelect(chapter)
            : () => ReaderRoute(
                mangaId: manga.id,
                chapterId: chapter.id,
                showReaderLayoutAnimation: true,
              ).push(context),
        onLongPress: () => toggleSelect(chapter),
      ),
    );
  }

  Widget _desktopRow(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final showChapterNumber =
        ref.watch(mangaChapterDisplayModeProvider) ==
        ChapterDisplay.chapterNumber;
    final read = chapter.isRead.ifNull();
    final readColor = cs.onSurface.withValues(alpha: 0.38);
    final bookmarked = chapter.isBookmarked.ifNull();
    final hovered = useState(false);
    final popping = useState(false);
    final optionsFocus = useMemoized(FocusNode.new);
    useEffect(() => optionsFocus.dispose, [optionsFocus]);
    final optionsFocused = useState(false);
    final showHoverActions = hovered.value || optionsFocused.value;
    final optionsButtonKey = useMemoized(GlobalKey.new);

    final allowPop = !context.reduceMotion;
    Future<void> toggleBookmark() async {
      await toggleChapterBookmark(ref, chapter);
      if (allowPop) {
        popping.value = true;
        Future.delayed(const Duration(milliseconds: 180), () {
          if (context.mounted) popping.value = false;
        });
      }
      await updateData();
    }

    void openOptions() {
      final box =
          optionsButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      onOpenMenu?.call(
        menuAnchorForRect(context, box.localToGlobal(Offset.zero) & box.size),
        () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    final title = showChapterNumber
        ? context.l10n.chapterNumber(chapter.formattedChapterNumber)
        : chapter.name;
    final scanlator = chapter.scanlator.isNotBlank ? chapter.scanlator! : '';
    final progress = chapter.pageCount > 0
        ? (chapter.lastPageRead / chapter.pageCount).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          onSecondaryTapAt?.call(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: Material(
          color: isSelected
              ? cs.secondaryContainer
              : isCurrent
              ? cs.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              final shift =
                  HardwareKeyboard.instance.logicalKeysPressed.contains(
                    LogicalKeyboardKey.shiftLeft,
                  ) ||
                  HardwareKeyboard.instance.logicalKeysPressed.contains(
                    LogicalKeyboardKey.shiftRight,
                  );
              onRowTap?.call(shift);
            },
            child: Container(
              height: 46,
              padding: const EdgeInsets.only(right: 4),
              decoration: isCurrent
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(color: cs.primary, width: 3),
                      ),
                    )
                  : null,
              child: Stack(
                children: [
                  Row(
                    children: [
                      if (selectionMode)
                        Checkbox(
                          value: isSelected,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => toggleSelect(chapter),
                        )
                      else
                        const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            color: read ? readColor : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 96,
                        child: Text(
                          scanlator,
                          style: TextStyle(
                            fontSize: 13,
                            color: read ? readColor : cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: Text(
                          int.tryParse(chapter.uploadDate).toDaysAgo(context),
                          style: TextStyle(
                            fontSize: 13,
                            color: read ? readColor : cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: bookmarked
                            ? AnimatedScale(
                                scale: popping.value ? 1.35 : 1.0,
                                duration: const Duration(milliseconds: 180),
                                child: IconButton(
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  tooltip: context.l10n.removeBookmark,
                                  onPressed: toggleBookmark,
                                  icon: Icon(
                                    Icons.bookmark_rounded,
                                    color: cs.primary,
                                  ),
                                ),
                              )
                            : showHoverActions
                            ? AnimatedScale(
                                scale: popping.value ? 1.35 : 1.0,
                                duration: const Duration(milliseconds: 180),
                                child: IconButton(
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  tooltip: context.l10n.bookmark,
                                  onPressed: toggleBookmark,
                                  icon: Icon(
                                    Icons.bookmark_outline_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      OfflineSaveButton(chapterId: chapter.id),
                      if (!manga.isLocalSource)
                        DownloadStatusIcon(
                          updateData: updateData,
                          chapter: chapter,
                          mangaId: manga.id,
                          isDownloaded: chapter.isDownloaded.ifNull(),
                        ),
                      SizedBox(
                        width: 32,
                        child: Visibility(
                          visible: showHoverActions,
                          maintainSize: true,
                          maintainState: true,
                          maintainAnimation: true,
                          child: Focus(
                            focusNode: optionsFocus,
                            onFocusChange: (v) => optionsFocused.value = v,
                            child: IconButton(
                              key: optionsButtonKey,
                              iconSize: 20,
                              padding: EdgeInsets.zero,
                              tooltip: context.l10n.more,
                              onPressed: openOptions,
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isCurrent && chapter.pageCount > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Tooltip(
                        message: context.l10n.pageOfTotal(
                          chapter.lastPageRead + 1,
                          chapter.pageCount,
                        ),
                        child: ClipRect(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
