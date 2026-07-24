// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/manga_details_controller.dart';
import 'tag_actions_menu.dart';

Future<void> _showAddTagDialog(
    BuildContext context, WidgetRef ref, int mangaId) async {
  final controller = TextEditingController();
  final tag = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.addTag),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: context.l10n.addTag),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
  if (tag != null && tag.trim().isNotEmpty) {
    await ref.read(mangaUserTagsProvider(mangaId: mangaId).notifier).add(tag);
  }
}

/// A compact "+" chip that opens the add-tag dialog. Sits at the front of the
/// genre chips so adding a tag reads as part of the tag list, not a stray button.
class AddUserTagChip extends ConsumerWidget {
  const AddUserTagChip({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    return GestureDetector(
      onTap: () => _showAddTagDialog(context, ref, mangaId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
        ),
        child: Icon(Icons.add_rounded, size: 16, color: cs.primary),
      ),
    );
  }
}

/// The user's own tags for a manga: deletable chips styled distinctly from the
/// source genre chips. Hidden entirely when there are none — the add affordance
/// lives inline with the genre chips as [AddUserTagChip].
class MangaUserTagsRow extends ConsumerWidget {
  const MangaUserTagsRow({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(mangaUserTagsProvider(mangaId: mangaId));
    if (tags.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(mangaUserTagsProvider(mangaId: mangaId).notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in tags)
            Builder(
              builder: (chipContext) => InputChip(
                avatar: Icon(Icons.sell_rounded,
                    size: 16,
                    color: context.theme.colorScheme.onSecondaryContainer),
                label: Text(tag),
                backgroundColor: context.theme.colorScheme.secondaryContainer,
                onPressed: () =>
                    showTagActionsMenu(chipContext, ref, tag: tag),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                onDeleted: () => notifier.remove(tag),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}
