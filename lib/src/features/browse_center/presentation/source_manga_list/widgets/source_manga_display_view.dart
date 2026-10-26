// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/selection_action_bar.dart';
import '../../../../library/presentation/library/controller/library_controller.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../../manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../manga_book/presentation/manga_details/widgets/add_to_library_category.dart';
import '../../../../manga_book/presentation/manga_details/widgets/duplicate_manga_dialog.dart';
import '../../../../manga_book/presentation/manga_details/widgets/migrate_duplicate.dart';
import '../../../domain/source/source_model.dart';
import '../controller/bulk_duplicate_flow.dart';
import '../controller/source_manga_controller.dart';
import 'source_manga_grid_view.dart';
import 'source_manga_list_view.dart';

class _ClearSelectionIntent extends Intent {
  const _ClearSelectionIntent();
}

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
    final DisplayMode displayMode =
        ref.watch(sourceDisplayModeProvider) ??
        DBKeys.sourceDisplayMode.initial;

    final selection = useState<Set<int>>(const {});
    final selecting = selection.value.isNotEmpty;
    final desktop = context.usesDesktopShell;
    final gridFocusNode = useFocusNode();

    // Use the container across awaits; the widget ref may be disposed.
    final container = ProviderScope.containerOf(context, listen: false);

    // Serialize adds so concurrent singles share one post-add snapshot.
    final addInFlight = useRef(false);
    final addBusy = useState(false);

    void toggleSelection(int id) {
      final next = {...selection.value};
      next.contains(id) ? next.remove(id) : next.add(id);
      selection.value = next;
      // Selection can start with focus elsewhere (menu, search box).
      if (desktop && next.isNotEmpty) gridFocusNode.requestFocus();
    }

    Future<int> addAndReflect(List<int> ids) async {
      if (ids.isEmpty) return 0;
      final result = await AsyncValue.guard(
        () =>
            container.read(mangaBookRepositoryProvider).addMangasToLibrary(ids),
      );
      if (result is! AsyncData<List<int>>) return 0;
      final addedIds = result.value;
      final idSet = addedIds.toSet();
      controller.mapItems(
        (m) => idSet.contains(m.id)
            ? m.copyWith(user: m.user.copyWith(inLibrary: true))
            : m,
      );
      container.invalidate(libraryMangaListProvider);
      return addedIds.length;
    }

    Future<void> addMangasToLibrary(List<MangaDto> selected) async {
      if (selected.isEmpty) return;
      if (addInFlight.value) return;
      addInFlight.value = true;
      addBusy.value = true;
      try {
        // Keep the autoDispose library alive for the read; a null lookup still adds.
        List<MangaDto>? library;
        final keepAlive = container.listen(
          libraryMangaListProvider,
          (_, _) {},
        );
        try {
          library = await container.read(libraryMangaListProvider.future);
        } catch (_) {
          library = null;
        } finally {
          keepAlive.close();
        }
        if (!context.mounted) return;

        final split = splitSelectionForDuplicates(
          selection: selected,
          library: library,
        );

        var added = await addAndReflect(split.cleanIds);
        var skipped = 0;
        if (!context.mounted) return;

        // Duplicate hits may refer to earlier selections, so resolve cards from both lists.
        final cardPool = [...?library, ...selected];
        final trackerNames = container.read(libraryTrackerNamesProvider);

        final queue = split.flagged;
        for (var i = 0; i < queue.length; i++) {
          final manga = queue[i];
          final hitIds = split.hitIdsByManga[manga.id] ?? const {};
          final duplicates = [
            for (final m in cardPool)
              if (hitIds.contains(m.id)) m,
          ];

          MangaDto? toOpen;
          final result = await showDialog<DuplicateDialogResult>(
            context: context,
            barrierDismissible: true, // barrier ⇒ null ⇒ cancel the queue
            builder: (_) => DuplicateMangaDialog(
              candidate: manga,
              duplicates: duplicates,
              certainIds: split.certainIdsByManga[manga.id] ?? const {},
              trackerNameOf: (id) => trackerNames[id],
              bulk: queue.length > 1,
              onMigrate: (dup) => migrateDuplicateIntoCandidate(
                ref,
                context,
                from: dup,
                to: manga,
              ),
              onOpenEntry: (m) => toOpen = m,
            ),
            animationStyle: context.motionStyle,
          );
          if (!context.mounted) return;

          var stop = false;
          switch (classifyDuplicateResult(result)) {
            case BulkDupAction.addThis:
              added += await addAndReflect([manga.id]);
            case BulkDupAction.addRest:
              added += await addAndReflect([
                for (var j = i; j < queue.length; j++) queue[j].id,
              ]);
              stop = true;
            case BulkDupAction.skipThis:
              skipped += 1;
            case BulkDupAction.skipRest:
              skipped += queue.length - i;
              stop = true;
            case BulkDupAction.handled:
              break; // migrate added the candidate + removed the source
            case BulkDupAction.openStop:
              final target = toOpen;
              if (target != null) MangaRoute(mangaId: target.id).push(context);
              stop = true;
            case BulkDupAction.cancelStop:
              stop = true;
          }
          if (!context.mounted) return;
          if (stop) break;
        }

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skipped > 0
                  ? context.l10n.bulkAddedSkipped(added, skipped)
                  : context.l10n.bulkAdded(added),
            ),
          ),
          snackBarAnimationStyle: context.snackBarMotionStyle,
        );
      } finally {
        addInFlight.value = false;
        if (context.mounted) addBusy.value = false;
      }
    }

    Future<void> addSelectionToLibrary() async {
      final ids = selection.value.toList();
      if (ids.isEmpty) return;
      final selected = [
        for (final m in controller.items ?? const <MangaDto>[])
          if (ids.contains(m.id)) m,
      ];
      selection.value = const {};
      await addMangasToLibrary(selected);
    }

    Future<void> addSingleToLibrary(MangaDto manga) async {
      if (addInFlight.value) return;
      addInFlight.value = true;
      addBusy.value = true;
      try {
        final result = await AsyncValue.guard(
          () => addMangaToLibraryWithCategory(ref, context, manga),
        );
        if (!context.mounted) return;
        if (result.hasError) {
          result.showToastOnError(container.read(toastProvider));
          return;
        }
        // Series flow returns void, so confirm the add before marking the tile.
        List<MangaDto>? library;
        try {
          library = await container.read(libraryMangaListProvider.future);
        } catch (_) {
          library = null;
        }
        if (library != null && library.any((m) => m.id == manga.id)) {
          controller.mapItems(
            (m) => m.id == manga.id
                ? m.copyWith(user: m.user.copyWith(inLibrary: true))
                : m,
          );
        }
      } finally {
        addInFlight.value = false;
        if (context.mounted) addBusy.value = false;
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
        onAddToLibrary: addSingleToLibrary,
        addEnabled: !addBusy.value,
      ),
      DisplayMode.list || DisplayMode.descriptiveList => SourceMangaListView(
        controller: controller,
        source: source,
        selectedIds: selection.value,
        selecting: selecting,
        onToggleSelection: toggleSelection,
      ),
      // Map saved comfortableGrid values to the source picker's supported grid.
      DisplayMode.coverOnly ||
      DisplayMode.comfortableGrid => SourceMangaGridView(
        sourceId: sourceId,
        sourceType: sourceType,
        controller: controller,
        source: source,
        selectedIds: selection.value,
        selecting: selecting,
        onToggleSelection: toggleSelection,
        onAddToLibrary: addSingleToLibrary,
        addEnabled: !addBusy.value,
      ),
    };

    void selectAll() => selection.value = {
      for (final m in controller.items ?? const <MangaDto>[]) m.id,
    };
    final desktopBody = Column(
      children: [
        if (selecting)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                IconButton(
                  tooltip: context.l10n.clearSelection,
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: () => selection.value = const {},
                ),
                Text(
                  context.l10n.numSelected(selection.value.length),
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: selectAll,
                  icon: const Icon(FluentIcons.select_all_on_24_regular),
                  label: Text(context.l10n.selectAll),
                ),
                TextButton.icon(
                  onPressed: addBusy.value ? null : addSelectionToLibrary,
                  style: TextButton.styleFrom(
                    foregroundColor: context.theme.colorScheme.primary,
                  ),
                  icon: const Icon(FluentIcons.heart_24_regular),
                  label: Text(context.l10n.addToLibrary),
                ),
              ],
            ),
          ),
        Expanded(
          child: Focus(focusNode: gridFocusNode, child: display),
        ),
      ],
    );
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) selection.value = const {};
      },
      child: desktop
          ? Shortcuts(
              shortcuts: {
                if (selecting)
                  const SingleActivator(LogicalKeyboardKey.escape):
                      const _ClearSelectionIntent(),
              },
              child: Actions(
                actions: {
                  _ClearSelectionIntent: CallbackAction<_ClearSelectionIntent>(
                    onInvoke: (_) {
                      selection.value = const {};
                      return null;
                    },
                  ),
                },
                child: desktopBody,
              ),
            )
          : Stack(
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
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () => selection.value = const {},
                        ),
                        Text(
                          '${selection.value.length}',
                          style: context.textTheme.titleMedium,
                        ),
                      ],
                      actions: [
                        IconButton(
                          tooltip: 'Select all',
                          icon: const Icon(
                            FluentIcons.select_all_on_24_regular,
                          ),
                          onPressed: selectAll,
                        ),
                        IconButton(
                          tooltip: context.l10n.addToLibrary,
                          icon: const Icon(FluentIcons.heart_24_regular),
                          onPressed: addBusy.value
                              ? null
                              : addSelectionToLibrary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
