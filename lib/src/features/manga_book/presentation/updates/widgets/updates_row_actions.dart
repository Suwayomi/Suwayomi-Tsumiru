// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../widgets/chapter_actions/chapter_bulk_actions.dart';
import '../../manga_details/controller/manga_details_controller.dart';
import '../../manga_details/widgets/chapter_context_menu.dart';

/// Holds the autoDispose provider open until the fetch settles.
Future<List<ChapterDto>?> loadSeriesChapters(WidgetRef ref, int mangaId) async {
  final provider = mangaChapterListProvider(mangaId: mangaId);
  final keepAlive = ref.listenManual(provider, (_, _) {});
  try {
    return await ref.read(provider.future);
  } finally {
    keepAlive.close();
  }
}

Future<void> showUpdatesChapterMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required ChapterDto chapter,
  required String? seriesUrl,
  required ValueNotifier<Map<int, ChapterDto>> selectedChapters,
  required ValueNotifier<int?> selectionAnchor,
  required List<ChapterDto> orderedChapters,
  required Future<void> Function(Set<int> mangaIds) refreshSeries,
  void Function()? refocus,
}) {
  final actingOnSelection = selectedChapters.value.containsKey(chapter.id);
  final mangaIds = actingOnSelection
      ? {for (final c in selectedChapters.value.values) c.mangaId}
      : {chapter.mangaId};
  return showChapterContextMenu(
    context: context,
    ref: ref,
    position: position,
    seriesUrl: seriesUrl,
    chapter: chapter,
    selectedChapters: selectedChapters,
    selectionAnchor: selectionAnchor,
    orderedChapters: orderedChapters,
    bulkChapters: orderedChapters,
    loadBulkChapters: () => loadSeriesChapters(ref, chapter.mangaId),
    refresh: () async {
      if (actingOnSelection) {
        selectedChapters.value = {};
        selectionAnchor.value = null;
      }
      await refreshSeries(mangaIds);
    },
    refocus: refocus,
    updatesMenu: true,
    onViewManga: () => MangaRoute(mangaId: chapter.mangaId).push(context),
  );
}

class UpdatesRowActions extends HookConsumerWidget {
  const UpdatesRowActions({
    super.key,
    required this.chapter,
    required this.seriesUrl,
    required this.selectedChapters,
    required this.selectionAnchor,
    required this.orderedChapters,
    required this.refreshSeries,
    required this.hovered,
  });
  final ChapterDto chapter;
  final String? seriesUrl;
  final ValueNotifier<Map<int, ChapterDto>> selectedChapters;
  final ValueNotifier<int?> selectionAnchor;
  final List<ChapterDto> orderedChapters;
  final Future<void> Function(Set<int> mangaIds) refreshSeries;
  final bool hovered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final bookmarked = chapter.user.isBookmarked.ifNull();
    final popping = useState(false);
    final optionsFocus = useMemoized(FocusNode.new);
    useEffect(() => optionsFocus.dispose, [optionsFocus]);
    final optionsFocused = useState(false);
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
      await refreshSeries({chapter.mangaId});
    }

    void openOptions() {
      final box =
          optionsButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      showUpdatesChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForRect(
          context,
          box.localToGlobal(Offset.zero) & box.size,
        ),
        chapter: chapter,
        seriesUrl: seriesUrl,
        selectedChapters: selectedChapters,
        selectionAnchor: selectionAnchor,
        orderedChapters: orderedChapters,
        refreshSeries: refreshSeries,
        refocus: () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    return IconButtonTheme(
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
            child: bookmarked
                ? AnimatedScale(
                    scale: popping.value ? 1.35 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: IconButton(
                      tooltip: context.l10n.removeBookmark,
                      onPressed: toggleBookmark,
                      icon: Icon(
                        FluentIcons.bookmark_24_filled,
                        color: cs.primary,
                      ),
                    ),
                  )
                : hovered
                ? AnimatedScale(
                    scale: popping.value ? 1.35 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: IconButton(
                      tooltip: context.l10n.bookmark,
                      onPressed: toggleBookmark,
                      icon: Icon(
                        FluentIcons.bookmark_24_regular,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : null,
          ),
          SizedBox(
            width: 32,
            child: Visibility(
              visible: hovered || optionsFocused.value,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: Focus(
                focusNode: optionsFocus,
                onFocusChange: (v) => optionsFocused.value = v,
                child: IconButton(
                  key: optionsButtonKey,
                  tooltip: context.l10n.more,
                  onPressed: openOptions,
                  icon: Icon(
                    FluentIcons.more_vertical_24_regular,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
