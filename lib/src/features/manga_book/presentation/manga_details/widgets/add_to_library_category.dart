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
import '../../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../../library/presentation/library/controller/library_controller.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../data/manga_book/manga_book_repository.dart';

/// Adds a manga to the library honoring the "Default category" preference:
/// a specific category is assigned silently, "Default"/uncategorized just adds,
/// and "Always ask" pops a picker. Mirrors Komikku's add-to-library behavior.
///
/// Assignment is client-side (the server does not auto-categorize on add, per
/// Suwayomi-WebUI). Returns without adding if the picker is cancelled.
Future<void> addMangaToLibraryWithCategory(
  WidgetRef ref,
  BuildContext context,
  int mangaId,
) async {
  final repo = ref.read(mangaBookRepositoryProvider);
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
