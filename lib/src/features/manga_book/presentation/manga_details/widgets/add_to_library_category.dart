// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../library/data/default_category.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../../library/domain/duplicate_entry_mapper.dart';
import '../../../../library/domain/duplicate_matcher.dart';
import '../../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../../library/presentation/library/controller/library_controller.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/manga/manga_model.dart';
import 'duplicate_manga_dialog.dart';
import 'migrate_duplicate.dart';

/// Assigns the preferred category client-side; cancelling the picker leaves the manga unadded.

Future<void> addMangaToLibraryWithCategory(
  WidgetRef ref,
  BuildContext context,
  MangaDto manga, {
  @visibleForTesting
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  @visibleForTesting
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  // Capture the container so writes and invalidation survive details-page disposal.
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(mangaBookRepositoryProvider);
  final mangaId = manga.id;

  if (!await _passesDuplicateGate(
    ref,
    container,
    context,
    manga,
    migrateDuplicate: migrateDuplicate,
    openEntry: openEntry,
  )) {
    return;
  }
  if (!context.mounted) return;

  final pref =
      container.read(libraryDefaultCategoryProvider) ??
      DBKeys.libraryDefaultCategory.initial as int;
  final defaultId = await container.read(defaultCategoryIdProvider.future);
  if (defaultId == null) throw StateError('Default category unavailable');
  final categories =
      (await container.read(categoryControllerProvider.future) ?? const [])
          .where((c) => c.id != defaultId)
          .toList();

  final match = categories.where((c) => c.id == pref).toList();
  if (match.isNotEmpty) {
    await repo.addMangaToLibrary(mangaId);
    await repo.addMangaToCategory(mangaId, match.first.id);
  } else if (pref == 0 || categories.isEmpty) {
    // A deleted category preference falls through to the picker, not the uncategorized branch.
    await repo.addMangaToLibrary(mangaId);
  } else {
    if (!context.mounted) return;
    final picked = await showDialog<List<int>>(
      context: context,
      animationStyle: context.motionStyle,
      builder: (context) => SetCategoriesOnAddDialog(categories: categories),
    );
    if (picked == null) return; // cancelled
    await repo.addMangaToLibrary(mangaId);
    for (final id in picked) {
      await repo.addMangaToCategory(mangaId, id);
    }
  }
  container.invalidate(libraryMangaListProvider);
}

/// Allow adds on duplicate-check read failure; false means opened, migrated, or cancelled.
Future<bool> _passesDuplicateGate(
  WidgetRef ref,
  ProviderContainer container,
  BuildContext context,
  MangaDto manga, {
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  List<MangaDto>? libraryOrNull;
  try {
    libraryOrNull = await container.read(libraryMangaListProvider.future);
  } catch (_) {
    libraryOrNull = null;
  }
  if (!context.mounted) return false;
  final library = libraryOrNull;
  if (library == null) return true; // list unavailable ⇒ fail open

  final entries = library.map(dupEntryFromManga).toList();
  final candidate = dupEntryFromManga(manga);
  final titleHits = titleDuplicates(
    candidateId: manga.id,
    candidateTitle: manga.title,
    entries: entries,
  );
  final trackerHits = trackerDuplicates(
    candidateId: manga.id,
    candidatePairs: candidate.trackerPairs,
    entries: entries,
  );
  final hitIds = {
    ...titleHits.map((e) => e.id),
    ...trackerHits.map((e) => e.id),
  };
  if (hitIds.isEmpty) return true;

  final trackerNames = container.read(libraryTrackerNamesProvider);
  final migrate =
      migrateDuplicate ??
      (MangaDto from, MangaDto to) =>
          migrateDuplicateIntoCandidate(ref, context, from: from, to: to);
  final open =
      openEntry ??
      (BuildContext ctx, MangaDto target) =>
          MangaRoute(mangaId: target.id).push(ctx);

  MangaDto? toOpen;
  final result = await showDialog<DuplicateDialogResult>(
    context: context,
    barrierDismissible: true, // barrier tap ⇒ null ⇒ cancel (below)
    builder: (_) => DuplicateMangaDialog(
      candidate: manga,
      duplicates: library.where((m) => hitIds.contains(m.id)).toList(),
      certainIds: trackerHits.map((e) => e.id).toSet(),
      trackerNameOf: (id) => trackerNames[id],
      onMigrate: (dup) => migrate(dup, manga),
      onOpenEntry: (m) => toOpen = m,
    ),
    animationStyle: context.motionStyle,
  );
  if (!context.mounted) return false;
  if (result == DuplicateDialogResult.openedEntry) {
    final target = toOpen;
    if (target != null) open(context, target);
    return false;
  }
  return result == DuplicateDialogResult.addAnyway;
}

/// Server-default categories start checked; returns selected IDs, or null on Cancel/Edit.
class SetCategoriesOnAddDialog extends HookWidget {
  const SetCategoriesOnAddDialog({super.key, required this.categories});

  final List<CategoryDto> categories;

  @override
  Widget build(BuildContext context) {
    final selected = useState<Set<int>>({
      for (final c in categories)
        if (c.defaultCategory) c.id,
    });
    return AlertDialog(
      title: Text(context.l10n.setCategories),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in categories)
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.value.contains(c.id),
                title: Text(c.name),
                onChanged: (value) {
                  final next = {...selected.value};
                  value.ifNull() ? next.add(c.id) : next.remove(c.id);
                  selected.value = next;
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            const EditCategoriesRoute().push(context);
          },
          child: Text(context.l10n.edit),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, selected.value.toList()),
          child: Text(context.l10n.ok),
        ),
      ],
    );
  }
}
