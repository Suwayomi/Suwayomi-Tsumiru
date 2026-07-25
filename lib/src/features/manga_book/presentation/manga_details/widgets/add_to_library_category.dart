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

/// Adds a manga to the library honoring the "Default category" preference:
/// a specific category is assigned silently, "Default"/uncategorized just adds,
/// and "Always ask" pops a picker. Mirrors Komikku's add-to-library behavior.
///
/// Assignment is client-side (the server does not auto-categorize on add, per
/// Suwayomi-WebUI). Returns without adding if the picker is cancelled.
Future<void> addMangaToLibraryWithCategory(
  WidgetRef ref,
  BuildContext context,
  MangaDto manga, {
  // Test seams: migrate needs the whole migration runner and open needs a
  // router, neither of which a widget test can stand up. Production leaves both
  // null and uses the real runner-backed migrate + go_router navigation.
  @visibleForTesting
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  @visibleForTesting
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  final repo = ref.read(mangaBookRepositoryProvider);
  final mangaId = manga.id;

  if (!await _passesDuplicateGate(
    ref,
    context,
    manga,
    migrateDuplicate: migrateDuplicate,
    openEntry: openEntry,
  )) {
    return;
  }
  if (!context.mounted) return;

  final pref = ref.read(libraryDefaultCategoryProvider) ??
      DBKeys.libraryDefaultCategory.initial as int;
  final categories =
      (await ref.read(categoryControllerProvider.future) ?? const [])
          // Default/uncategorized (id 0) is not a real assignable target.
          .where((c) => c.id != 0)
          .toList();

  final match = categories.where((c) => c.id == pref).toList();
  if (match.isNotEmpty) {
    await repo.addMangaToLibrary(mangaId);
    await repo.addMangaToCategory(mangaId, match.first.id);
  } else if (pref == 0 || categories.isEmpty) {
    // Explicit Default/uncategorized, or nothing to pick from. A since-deleted
    // pref is NOT this branch — it falls through to the picker (matches settings).
    await repo.addMangaToLibrary(mangaId);
  } else {
    if (!context.mounted) return;
    final picked = await showDialog<List<int>>(
      context: context,
      builder: (context) => SetCategoriesOnAddDialog(categories: categories),
    );
    if (picked == null) return; // cancelled
    await repo.addMangaToLibrary(mangaId);
    for (final id in picked) {
      await repo.addMangaToCategory(mangaId, id);
    }
  }
  ref.invalidate(libraryMangaListProvider);
}

/// Runs the possible-duplicates check (#118) before the add. Returns true when
/// the add should proceed (no duplicates, a fail-open library-list error, or the
/// user chose "Add anyway"); false when it should stop (migrated / opened an
/// existing entry / cancelled). Fail-open is deliberate — a library read that
/// errors must never block adding.
Future<bool> _passesDuplicateGate(
  WidgetRef ref,
  BuildContext context,
  MangaDto manga, {
  Future<bool> Function(MangaDto from, MangaDto to)? migrateDuplicate,
  void Function(BuildContext context, MangaDto manga)? openEntry,
}) async {
  List<MangaDto>? libraryOrNull;
  try {
    libraryOrNull = await ref.read(libraryMangaListProvider.future);
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

  final trackerNames = ref.read(libraryTrackerNamesProvider);
  final migrate = migrateDuplicate ??
      (MangaDto from, MangaDto to) =>
          migrateDuplicateIntoCandidate(ref, context, from: from, to: to);
  final open = openEntry ??
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
  );
  if (!context.mounted) return false;
  if (result == DuplicateDialogResult.openedEntry) {
    final target = toOpen;
    if (target != null) open(context, target);
    return false;
  }
  // Barrier-dismiss (null), cancel, and migrated all stop the add.
  return result == DuplicateDialogResult.addAnyway;
}

/// The "Always ask" prompt shown when adding a manga to the library: pick which
/// categories it joins. Server-default categories start checked (WebUI parity).
/// Pops the selected ids on OK, or null on Cancel/Edit.
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
            const EditCategoriesRoute().go(context);
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
