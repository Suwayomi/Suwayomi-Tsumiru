// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../controller/manga_details_controller.dart';
import '../controller/scanlator_dedup.dart';

/// Set-once ranking dialog for issue #141's preferred-scanlator-groups
/// feature: checked groups (in drag order) become the preference; unchecked
/// groups fall back to source order at dedup time.
class ScanlatorPreferenceDialog extends HookConsumerWidget {
  const ScanlatorPreferenceDialog({super.key, required this.mangaId});
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final derived = ref.watch(mangaScanlatorListProvider(mangaId: mangaId));
    final saved =
        ref.watch(mangaPreferredScanlatorsProvider(mangaId: mangaId));
    // Union: a ranked group whose chapters vanished from the source must stay
    // visible so it can be unranked.
    final allGroups = {...derived, ...saved};
    final ranked = useState<List<String>>([...saved]);

    String label(String g) =>
        g == kUnknownScanlatorGroup ? context.l10n.unknownScanlator : g;

    final unranked = [
      for (final g in allGroups)
        if (!ranked.value.contains(g)) g,
    ]..sort(
        (a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()));

    return AlertDialog(
      title: Text(context.l10n.preferredScanlationGroups),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              context.l10n.preferredGroupsHint,
              style: context.textTheme.bodySmall,
            ),
            if (ranked.value.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                onReorder: (oldIndex, newIndex) {
                  final list = [...ranked.value];
                  if (newIndex > oldIndex) newIndex--;
                  list.insert(newIndex, list.removeAt(oldIndex));
                  ranked.value = list;
                },
                children: [
                  for (final g in ranked.value)
                    CheckboxListTile(
                      key: ValueKey('ranked-$g'),
                      value: true,
                      title: Text(label(g)),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (_) =>
                          ranked.value = [...ranked.value]..remove(g),
                    ),
                ],
              ),
            for (final g in unranked)
              CheckboxListTile(
                key: ValueKey('unranked-$g'),
                value: false,
                title: Text(label(g)),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (_) => ranked.value = [...ranked.value, g],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () async {
            var ok = false;
            try {
              ok = await ref
                  .read(mangaPreferredScanlatorsProvider(mangaId: mangaId)
                      .notifier)
                  .setPreference(ranked.value);
            } catch (_) {}
            if (!context.mounted) return;
            if (!ok) {
              ref.read(toastProvider)?.showError(
                    context.l10n.errorSomethingWentWrong,
                  );
              return;
            }
            Navigator.of(context).pop();
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
