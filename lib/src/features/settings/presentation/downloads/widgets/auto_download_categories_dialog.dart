// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../library/domain/category/category_model.dart';
import '../../../../library/presentation/category/controller/edit_category_controller.dart';

/// Normalises a category's include/exclude flag to the three values we cycle
/// (graphql_codegen adds a `$unknown` member we never surface).
Enum$IncludeOrExclude coerceInclude(Enum$IncludeOrExclude? v) =>
    v == Enum$IncludeOrExclude.INCLUDE || v == Enum$IncludeOrExclude.EXCLUDE
        ? v!
        : Enum$IncludeOrExclude.UNSET;

/// Summary line for the "Categories" row under Settings → Download → Auto
/// download. "All categories" when nothing is included/excluded, else a
/// short "Included … / Excluded …" string.
String autoDownloadCategoriesSummary(
    BuildContext context, List<CategoryDto> categories) {
  final included = categories
      .where((c) => c.includeInDownload == Enum$IncludeOrExclude.INCLUDE)
      .map((c) => c.name);
  final excluded = categories
      .where((c) => c.includeInDownload == Enum$IncludeOrExclude.EXCLUDE)
      .map((c) => c.name);
  if (included.isEmpty && excluded.isEmpty) {
    return context.l10n.autoDownloadCategoriesAll;
  }
  final parts = <String>[
    if (included.isNotEmpty)
      context.l10n.autoDownloadCategoriesIncluded(included.join(', ')),
    if (excluded.isNotEmpty)
      context.l10n.autoDownloadCategoriesExcluded(excluded.join(', ')),
  ];
  return parts.join(' · ');
}

/// Tri-state (default / include / exclude) picker for which categories
/// auto-download new chapters — the Suwayomi `includeInDownload` flag per
/// category. Tapping a row cycles default → include → exclude → default.
class AutoDownloadCategoriesDialog extends ConsumerWidget {
  const AutoDownloadCategoriesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryControllerProvider);
    return categories.when(
      loading: () => const AlertDialog(
        content: SizedBox(
            height: 80, child: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => AlertDialog(
        title: Text(context.l10n.autoDownloadCategories),
        content: Text(context.l10n.errorSomethingWentWrong),
        actions: const [PopButton()],
      ),
      data: (cats) => _Body(categories: cats ?? const []),
    );
  }
}

class _Body extends HookConsumerWidget {
  const _Body({required this.categories});

  final List<CategoryDto> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seeded once from the loaded list (the parent only builds this with data).
    final state = useState<Map<int, Enum$IncludeOrExclude>>({
      for (final c in categories) c.id: coerceInclude(c.includeInDownload),
    });

    void cycle(int id) {
      final cur = state.value[id] ?? Enum$IncludeOrExclude.UNSET;
      final next = switch (cur) {
        Enum$IncludeOrExclude.UNSET => Enum$IncludeOrExclude.INCLUDE,
        Enum$IncludeOrExclude.INCLUDE => Enum$IncludeOrExclude.EXCLUDE,
        _ => Enum$IncludeOrExclude.UNSET,
      };
      state.value = {...state.value, id: next};
    }

    // Flutter tri-state checkbox: true ✓ = include, null – = exclude,
    // false (empty) = default/unset.
    bool? checkboxValue(Enum$IncludeOrExclude v) => switch (v) {
          Enum$IncludeOrExclude.INCLUDE => true,
          Enum$IncludeOrExclude.EXCLUDE => null,
          _ => false,
        };

    Future<void> save() async {
      final controller = ref.read(categoryControllerProvider.notifier);
      for (final c in categories) {
        final next = state.value[c.id] ?? Enum$IncludeOrExclude.UNSET;
        if (next != coerceInclude(c.includeInDownload)) {
          await controller.editCategory(
              c.id, CategoryUpdate(includeInDownload: next));
        }
      }
      ref.invalidate(categoryControllerProvider);
    }

    return AlertDialog(
      title: Text(context.l10n.autoDownloadCategories),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                context.l10n.autoDownloadCategoriesHint,
                style: TextStyle(
                  fontSize: 12,
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: categories.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.autoDownloadCategoriesAll),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in categories)
                          CheckboxListTile(
                            dense: true,
                            tristate: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: checkboxValue(
                                state.value[c.id] ?? Enum$IncludeOrExclude.UNSET),
                            title: Text(c.name),
                            onChanged: (_) => cycle(c.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        const PopButton(),
        ElevatedButton(
          onPressed: () async {
            await save();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
