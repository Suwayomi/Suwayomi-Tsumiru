import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../offline/data/offline_repository.dart';
import '../controller/manga_details_controller.dart';
import 'manga_notes_save.dart';
import 'manga_notes_toolbar.dart';

class MangaNotesDialog extends HookConsumerWidget {
  const MangaNotesDialog({
    super.key,
    required this.mangaId,
    required this.seriesTitle,
    required this.initialNotes,
    required this.existingMetas,
  });

  final int mangaId;
  final String seriesTitle;
  final String initialNotes;
  final Map<String, String> existingMetas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController(text: initialNotes);
    final saving = useState(false);

    Future<void> save() async {
      if (saving.value) return;
      saving.value = true;
      if (controller.text.trimRight().isEmpty &&
          initialNotes.trimRight().isNotEmpty) {
        if (!await confirmAction(
              context,
              title: context.l10n.confirmDeleteNoteTitle,
              message: context.l10n.confirmDeleteNoteMessage,
              action: context.l10n.delete,
            ) ||
            !context.mounted) {
          if (context.mounted) saving.value = false;
          return;
        }
      }
      final ok = await persistMangaNotes(
        client: ref.read(graphQlClientProvider),
        mangaId: mangaId,
        rawText: controller.text,
        existingMetas: existingMetas,
        offlineDb: ref.read(offlineReadDatabaseProvider),
        onSaved: () => ref.invalidate(mangaWithIdProvider(mangaId: mangaId)),
      );
      if (!context.mounted) return;
      if (!ok) {
        saving.value = false;
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
        return;
      }
      Navigator.of(context).pop();
    }

    final cs = context.theme.colorScheme;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.editNotes),
          Text(
            seriesTitle,
            style: context.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MangaNotesFormatToolbar(controller: controller),
              Divider(height: 1, color: cs.outlineVariant),
              SizedBox(
                height: 240,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: context.l10n.notes,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: saving.value ? null : save,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
