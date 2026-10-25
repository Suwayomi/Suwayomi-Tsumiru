// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../controller/manga_details_controller.dart';
import '../controller/scanlator_dedup.dart';

/// Checked groups in drag order become preferences; unchecked groups remain reader fallbacks.
class ScanlatorPreferenceDialog extends HookConsumerWidget {
  const ScanlatorPreferenceDialog({super.key, required this.mangaId});
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final derived = ref.watch(mangaScanlatorListProvider(mangaId: mangaId));
    final saved = ref.watch(mangaPreferredScanlatorsProvider(mangaId: mangaId));
    // Union: a ranked group whose chapters vanished from the source must stay
    // visible so it can be unranked.
    final allGroups = {...derived, ...saved};
    final ranked = useState<List<String>>([...saved]);

    String label(String g) =>
        g == kUnknownScanlatorGroup ? context.l10n.unknownScanlator : g;

    final unranked = [
      for (final g in allGroups)
        if (!ranked.value.contains(g)) g,
    ]..sort((a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()));

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
                buildDefaultDragHandles: false,
                onReorderItem: (oldIndex, newIndex) {
                  final list = [...ranked.value];
                  list.insert(newIndex, list.removeAt(oldIndex));
                  ranked.value = list;
                },
                children: [
                  for (var i = 0; i < ranked.value.length; i++)
                    _RankedGroupTile(
                      key: ValueKey('ranked-${ranked.value[i]}'),
                      index: i,
                      title: label(ranked.value[i]),
                      onRemove: () =>
                          ranked.value = [...ranked.value]
                            ..remove(ranked.value[i]),
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
                  .read(
                    mangaPreferredScanlatorsProvider(mangaId: mangaId).notifier,
                  )
                  .setPreference(ranked.value);
            } catch (_) {}
            if (!context.mounted) return;
            if (!ok) {
              ref
                  .read(toastProvider)
                  ?.showError(context.l10n.errorSomethingWentWrong);
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

class _RankedGroupTile extends StatelessWidget {
  const _RankedGroupTile({
    super.key,
    required this.index,
    required this.title,
    required this.onRemove,
  });

  final int index;
  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final desktop =
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;
    final tile = CheckboxListTile(
      value: true,
      title: Text(title),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (_) => onRemove(),
      secondary: desktop
          ? ReorderableDragStartListener(
              index: index,
              child: const Icon(FluentIcons.re_order_24_regular),
            )
          : null,
    );
    if (desktop) return tile;
    return ReorderableDelayedDragStartListener(index: index, child: tile);
  }
}
