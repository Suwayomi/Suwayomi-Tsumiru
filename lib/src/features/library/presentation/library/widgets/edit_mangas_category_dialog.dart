// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/default_category.dart';
import '../../category/controller/edit_category_controller.dart';
import '../controller/library_manga_list.dart';

/// Mixed categories stay unchanged unless tapped; a tap adds all unless already all-in.

class EditMangasCategoryDialog extends HookConsumerWidget {
  const EditMangasCategoryDialog({super.key, required this.mangas});
  final List<MangaDto> mangas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultId = ref.watch(settledDefaultCategoryIdProvider);
    final categories = (ref.watch(categoryControllerProvider).value ?? const [])
        .where((c) => defaultId != null && c.id != defaultId)
        .toList();

    final memberIds = [
      for (final m in mangas) {for (final n in m.categories.nodes) n.id},
    ];
    final initial = useMemoized<Map<int, bool?>>(
      () => {
        for (final c in categories) c.id: categoryMembership(memberIds, c.id),
      },
      [categories.map((c) => c.id).join(','), mangas.length],
    );
    // Seed synchronously for the first frame; the effect handles later category changes.
    final current = useState<Map<int, bool?>>({...initial});
    useEffect(() {
      current.value = {...initial};
      return null;
    }, [initial]);

    Future<void> apply() async {
      final addTo = <int>[];
      final removeFrom = <int>[];
      for (final c in categories) {
        final now = current.value[c.id];
        if (now == initial[c.id]) continue; // untouched → leave as-is
        if (now == true) {
          addTo.add(c.id);
        } else if (now == false) {
          removeFrom.add(c.id);
        }
      }
      if (addTo.isEmpty && removeFrom.isEmpty) {
        if (context.mounted) Navigator.pop(context);
        return;
      }
      final toast = ref.read(toastProvider);
      try {
        await ref
            .read(mangaBookRepositoryProvider)
            .updateMangasCategories(
              [for (final m in mangas) m.id],
              addTo: addTo,
              removeFrom: removeFrom,
            );
      } catch (e) {
        toast?.showError(e.toString());
        return; // keep the dialog open so the user can retry
      }
      ref.invalidate(libraryMangaListProvider);
      ref.invalidate(categoryControllerProvider);
      if (context.mounted) Navigator.pop(context);
    }

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.editCategory),
          Text('${mangas.length} series', style: context.textTheme.bodySmall),
        ],
      ),
      contentPadding: KEdgeInsets.h8v16.size,
      content: categories.isEmpty
          ? Padding(
              padding: KEdgeInsets.h16.size,
              child: Text(context.l10n.noCategoriesFoundAlt),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: context.height * .6),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in categories)
                      CheckboxListTile(
                        tristate: true,
                        value: current.value[c.id],
                        title: Text(c.name),
                        onChanged: (_) {
                          current.value = {
                            ...current.value,
                            c.id: current.value[c.id] == true ? false : true,
                          };
                        },
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: categories.isEmpty ? null : apply,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

/// true means all selected series, false none, and null mixed membership.
bool? categoryMembership(List<Set<int>> perMangaCategoryIds, int categoryId) {
  if (perMangaCategoryIds.isEmpty) return false;
  final inCount = perMangaCategoryIds
      .where((ids) => ids.contains(categoryId))
      .length;
  if (inCount == 0) return false;
  if (inCount == perMangaCategoryIds.length) return true;
  return null;
}
