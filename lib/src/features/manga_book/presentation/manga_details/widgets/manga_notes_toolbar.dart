import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import 'manga_notes_formatting.dart';

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
          icon: const Icon(FluentIcons.text_bold_24_regular),
          onPressed: () => apply((value) => applyInlineMarker(value, '**')),
        ),
        IconButton(
          tooltip: context.l10n.italic,
          icon: const Icon(FluentIcons.text_italic_24_regular),
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
          icon: const Icon(FluentIcons.text_bullet_list_ltr_24_regular),
          onPressed: () => apply(toggleBulletedList),
        ),
        IconButton(
          tooltip: context.l10n.numberedList,
          icon: const Icon(FluentIcons.text_number_list_ltr_24_regular),
          onPressed: () => apply(toggleNumberedList),
        ),
      ],
    );
  }
}
