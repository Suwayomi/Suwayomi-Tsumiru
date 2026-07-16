// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import 'controller/edit_category_controller.dart';
import 'widgets/category_create_fab.dart';
import 'widgets/category_tile.dart';

class EditCategoryScreen extends HookConsumerWidget {
  const EditCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryList = ref.watch(categoryControllerProvider);

    useEffect(() {
      categoryList.showToastOnError(
        ref.read(toastProvider),
        withMicrotask: true,
      );
      return;
    }, [categoryList.value]);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.editCategory),
      ),
      floatingActionButton: categoryList.asError?.error != null
          ? null
          : const CategoryCreateFab(),
      body: categoryList.showUiWhenData(
        context,
        (data) {
          if (data.isBlank ||
              (data.isSingletonList && data?.firstOrNull?.id == 0)) {
            return Emoticons(
              title: context.l10n.noCategoriesFound,
              button: TextButton(
                onPressed: () => ref.refresh(categoryControllerProvider.future),
                child: Text(context.l10n.refresh),
              ),
            );
          } else {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(categoryControllerProvider.future),
              child: ReorderableListView.builder(
                // Custom drag handles live in CategoryTile (and the default
                // category has none), so suppress the built-in trailing ones.
                buildDefaultDragHandles: false,
                itemCount: data!.length,
                itemBuilder: (context, index) {
                  final category = data[index];
                  return CategoryTile(
                    key: ValueKey(category.id),
                    index: index,
                    category: category,
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  // The pinned "Default" category sits at order 0: it can't be
                  // moved, and nothing else may take slot 0.
                  if (oldIndex == 0) return;
                  if (newIndex < 1) newIndex = 1;
                  if (newIndex == oldIndex) return;
                  final moved = data[oldIndex];
                  // reorderCategory takes the server `order` value, not the raw
                  // list index — use the order of whatever currently occupies
                  // the drop slot.
                  final targetOrder =
                      data[newIndex].order.getValueOnNullOrNegative();
                  ref
                      .read(categoryControllerProvider.notifier)
                      .reorderCategory(moved.id, targetOrder);
                },
              ),
            );
          }
        },
        refresh: () => ref.refresh(categoryControllerProvider.future),
      ),
    );
  }
}
