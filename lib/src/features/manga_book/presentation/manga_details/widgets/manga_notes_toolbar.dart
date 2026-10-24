import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import 'manga_notes_formatting.dart';

/// Bold / Italic / bulleted / numbered buttons inserting plain Markdown
/// markers into [controller]. The phone page adds a character count beside
/// this row; the desktop dialog shows it alone above the text field.
class MangaNotesFormatToolbar extends StatelessWidget {
  const MangaNotesFormatToolbar({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    void apply(TextEditingValue Function(TextEditingValue) edit) {
      controller.value = edit(controller.value);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.bold,
          icon: const Icon(Icons.format_bold_rounded),
          onPressed: () => apply((value) => applyInlineMarker(value, '**')),
        ),
        IconButton(
          tooltip: context.l10n.italic,
          icon: const Icon(Icons.format_italic_rounded),
          onPressed: () => apply((value) => applyInlineMarker(value, '*')),
        ),
        SizedBox(
          height: 24,
          child: VerticalDivider(
            width: 13,
            thickness: 1,
            color: context.colorScheme.outlineVariant,
          ),
        ),
        IconButton(
          tooltip: context.l10n.bulletedList,
          icon: const Icon(Icons.format_list_bulleted_rounded),
          onPressed: () => apply(toggleBulletedList),
        ),
        IconButton(
          tooltip: context.l10n.numberedList,
          icon: const Icon(Icons.format_list_numbered_rounded),
          onPressed: () => apply(toggleNumberedList),
        ),
      ],
    );
  }
}
