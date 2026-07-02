// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../domain/category/category_model.dart';
import '../controller/edit_category_controller.dart';
import 'edit_category_dialog.dart';

/// A category row in the Edit Categories screen: drag handle · name
/// (struck-through + dimmed when hidden) · edit · hide-toggle · delete.
class CategoryTile extends HookConsumerWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.index,
  });

  final CategoryDto category;

  /// Position in the reorderable list — used by the drag handle.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The pinned "Default" category (id 0 / order 0) can't be reordered or
    // deleted, so it gets no drag handle and a disabled delete (parity with the
    // old behaviour + the backend reserving order 0).
    final isDefault = category.id == 0 || category.order == 0;
    final isHidden = category.isHidden;
    final baseColor = context.theme.colorScheme.onSurface;

    return Card(
      margin: KEdgeInsets.h16v4.size,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        child: Row(
          children: [
            if (!isDefault)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(Icons.label_rounded, color: Colors.grey),
              ),
            Expanded(
              child: Text(
                category.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHidden ? baseColor.withValues(alpha: 0.6) : null,
                  decoration:
                      isHidden ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.editCategory,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => EditCategoryDialog(
                  category: category,
                  editCategory: (updated) => ref
                      .read(categoryControllerProvider.notifier)
                      .editCategory(category.id, updated),
                ),
              ),
              icon: const Icon(Icons.edit_rounded),
              color: Colors.grey,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isHidden
                  ? context.l10n.showCategory
                  : context.l10n.hideCategory,
              onPressed: () => ref
                  .read(categoryControllerProvider.notifier)
                  .setHidden(category.id, !isHidden),
              icon: Icon(
                isHidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              color: Colors.grey,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.delete,
              onPressed: !isDefault
                  ? () => showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(context.l10n.deleteCategoryTitle),
                          content:
                              Text(context.l10n.deleteCategoryDescription),
                          actions: [
                            const PopButton(),
                            ElevatedButton(
                              onPressed: () {
                                ref
                                    .read(categoryControllerProvider.notifier)
                                    .deleteCategory(category.id);
                                Navigator.pop(context);
                              },
                              child: Text(context.l10n.delete),
                            ),
                          ],
                        ),
                      )
                  : null,
              icon: const Icon(Icons.delete_rounded),
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
