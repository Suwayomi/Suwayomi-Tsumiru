// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/selection_action_bar.dart';
import '../../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../domain/source/source_model.dart';
import '../controller/source_manga_controller.dart';
import 'source_manga_grid_view.dart';
import 'source_manga_list_view.dart';

class SourceMangaDisplayView extends HookConsumerWidget {
  const SourceMangaDisplayView({
    super.key,
    required this.controller,
    required this.sourceId,
    required this.sourceType,
    this.source,
  });

  final PagingController<int, MangaDto> controller;
  final SourceDto? source;
  final String sourceId;
  final SourceType sourceType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DisplayMode displayMode = ref.watch(sourceDisplayModeProvider) ??
        DBKeys.sourceDisplayMode.initial;

    // Multi-select: long-press a cover to start selecting, tap to add/remove,
    // then bulk-add the whole selection to the library. Mirrors the library
    // grid's selection model.
    final selection = useState<Set<int>>(const {});
    final selecting = selection.value.isNotEmpty;

    void toggleSelection(int id) {
      final next = {...selection.value};
      next.contains(id) ? next.remove(id) : next.add(id);
      selection.value = next;
    }

    Future<void> addSelectionToLibrary() async {
      final ids = selection.value.toList();
      if (ids.isEmpty) return;
      selection.value = const {};
      final result = await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).addMangasToLibrary(ids),
      );
      if (result is AsyncError) return;
      // Reflect the new library membership on the already-loaded covers.
      final items = [...?controller.itemList];
      final idSet = ids.toSet();
      for (var i = 0; i < items.length; i++) {
        if (idSet.contains(items[i].id)) {
          items[i] = items[i].copyWith(inLibrary: true);
        }
      }
      controller.itemList = items;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Added ${ids.length} to library'),
        ));
      }
    }

    final display = switch (displayMode) {
      DisplayMode.grid => SourceMangaGridView(
          sourceId: sourceId,
          sourceType: sourceType,
          controller: controller,
          source: source,
          selectedIds: selection.value,
          selecting: selecting,
          onToggleSelection: toggleSelection,
        ),
      DisplayMode.list || DisplayMode.descriptiveList => SourceMangaListView(
          controller: controller,
          source: source,
          selectedIds: selection.value,
          selecting: selecting,
          onToggleSelection: toggleSelection,
        ),
      // comfortableGrid isn't offered in the source display picker; map it to
      // the grid so the exhaustive switch stays safe.
      DisplayMode.coverOnly ||
      DisplayMode.comfortableGrid =>
        SourceMangaGridView(
          sourceId: sourceId,
          sourceType: sourceType,
          controller: controller,
          source: source,
          selectedIds: selection.value,
          selecting: selecting,
          onToggleSelection: toggleSelection,
        ),
    };

    // While selecting, swallow the system back to clear the selection first,
    // and float the action bar over the grid.
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) selection.value = const {};
      },
      child: Stack(
        children: [
          display,
          if (selecting)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SelectionActionBar(
                clearsSystemNav: true,
                leading: [
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => selection.value = const {},
                  ),
                  Text('${selection.value.length}',
                      style: context.textTheme.titleMedium),
                ],
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => selection.value = {
                      for (final m in controller.itemList ?? const <MangaDto>[])
                        m.id,
                    },
                  ),
                  IconButton(
                    tooltip: context.l10n.addToLibrary,
                    icon: const Icon(Icons.favorite_rounded),
                    onPressed: addSelectionToLibrary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
