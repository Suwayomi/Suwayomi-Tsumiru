// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/network/graphql_errors.dart';
import '../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../data/default_category.dart';
import '../../../domain/category/category_model.dart';
import '../controller/edit_category_controller.dart';
import 'edit_category_dialog.dart';

/// A category row in the Edit Categories screen: drag handle · name
/// (struck-through + dimmed when hidden) · edit · hide-toggle · delete.

class CategoryTile extends HookConsumerWidget {
  const CategoryTile({super.key, required this.category, required this.index});

  final CategoryDto category;

  /// Position in the reorderable list — used by the drag handle.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultId = ref.watch(settledDefaultCategoryIdProvider);
    final isDefault = defaultId == null || category.id == defaultId;
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
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(
                  Icons.label_rounded,
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Expanded(
              child: Text(
                category.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHidden ? baseColor.withValues(alpha: 0.6) : null,
                  decoration: isHidden ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.editCategory,
              onPressed: isDefault
                  ? null
                  : () => showDialog(
                      context: context,
                      builder: (context) => EditCategoryDialog(
                        category: category,
                        editCategory: (updated) => ref
                            .read(categoryControllerProvider.notifier)
                            .editCategory(category.id, updated),
                      ),
                    ),
              icon: const Icon(Icons.edit_rounded),
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isHidden
                  ? context.l10n.showCategory
                  : context.l10n.hideCategory,
              // The flag lives on the server; offline the change lands on the
              // device mirror instead (a hidden category's downloads must stay
              // reachable), and the server's flag returns on reconnect.
              onPressed: () async {
                final result = await ref
                    .read(categoryControllerProvider.notifier)
                    .setHidden(category.id, !isHidden);
                if (!context.mounted) return;
                switch (result) {
                  case AsyncData(value: CategoryVisibilityOutcome.deviceOnly):
                    ref
                        .read(toastProvider)
                        ?.show(context.l10n.categoryVisibilityDeviceOnly);
                  case AsyncError(:final error):
                    ref
                        .read(toastProvider)
                        ?.showError(
                          isConnectionError(
                                error is OperationMessageException
                                    ? error.exception
                                    : error,
                              )
                              ? context.l10n.needsServerConnection
                              : context.l10n.errorSomethingWentWrong,
                        );
                  default:
                }
              },
              icon: Icon(
                isHidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.l10n.delete,
              onPressed: !isDefault
                  ? () => showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(dialogContext.l10n.deleteCategoryTitle),
                        content: Text(
                          dialogContext.l10n.deleteCategoryDescription,
                        ),
                        actions: [
                          const PopButton(),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              final result = await ref
                                  .read(categoryControllerProvider.notifier)
                                  .deleteCategory(category.id);
                              // Use the tile context because the dialog has already closed.
                              if (result is AsyncError && context.mounted) {
                                final error = result.error;
                                final cause = error is OperationMessageException
                                    ? error.exception
                                    : error;
                                ref
                                    .read(toastProvider)
                                    ?.showError(
                                      isConnectionError(cause)
                                          ? context.l10n.needsServerConnection
                                          : context
                                                .l10n
                                                .errorSomethingWentWrong,
                                    );
                              }
                            },
                            child: Text(dialogContext.l10n.delete),
                          ),
                        ],
                      ),
                    )
                  : null,
              icon: const Icon(Icons.delete_rounded),
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
