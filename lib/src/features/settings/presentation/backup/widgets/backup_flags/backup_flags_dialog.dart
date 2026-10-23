import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import 'backup_flags.dart';

Future<BackupFlags?> showBackupFlagsDialog(
  BuildContext context, {
  required String title,
  BackupFlags? initial,
}) => showDialog<BackupFlags>(
  context: context,
  animationStyle: context.motionStyle,
  builder: (context) =>
      BackupFlagsDialog(title: title, initial: initial ?? const BackupFlags()),
);

class BackupFlagsDialog extends HookWidget {
  const BackupFlagsDialog({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final BackupFlags initial;

  @override
  Widget build(BuildContext context) {
    final flags = useState(initial);
    CheckboxListTile tile(String label, bool value, ValueChanged<bool> set) =>
        CheckboxListTile(
          title: Text(label),
          value: value,
          onChanged: (changed) => set(changed.ifNull()),
        );
    Text header(String text) =>
        Text(text, style: Theme.of(context).textTheme.titleSmall);
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context.l10n.library),
            tile(
              context.l10n.includeManga,
              flags.value.includeManga,
              (value) =>
                  flags.value = flags.value.copyWith(includeManga: value),
            ),
            tile(
              context.l10n.includeChapters,
              flags.value.includeChapters,
              (value) =>
                  flags.value = flags.value.copyWith(includeChapters: value),
            ),
            tile(
              context.l10n.includeTracking,
              flags.value.includeTracking,
              (value) =>
                  flags.value = flags.value.copyWith(includeTracking: value),
            ),
            tile(
              context.l10n.includeHistory,
              flags.value.includeHistory,
              (value) =>
                  flags.value = flags.value.copyWith(includeHistory: value),
            ),
            tile(
              context.l10n.includeCategories,
              flags.value.includeCategories,
              (value) =>
                  flags.value = flags.value.copyWith(includeCategories: value),
            ),
            const SizedBox(height: 8),
            header(context.l10n.settings),
            tile(
              context.l10n.includeClientData,
              flags.value.includeClientData,
              (value) =>
                  flags.value = flags.value.copyWith(includeClientData: value),
            ),
            tile(
              context.l10n.includeServerSettings,
              flags.value.includeServerSettings,
              (value) => flags.value = flags.value.copyWith(
                includeServerSettings: value,
              ),
            ),
          ],
        ),
      ),
      actions: [
        PopButton(popText: context.l10n.cancel),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, flags.value),
          child: Text(context.l10n.okButton),
        ),
      ],
    );
  }
}
