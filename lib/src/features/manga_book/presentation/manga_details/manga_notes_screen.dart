import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import 'widgets/manga_notes_save.dart';
import 'widgets/manga_notes_toolbar.dart';

class MangaNotesScreen extends HookConsumerWidget {
  const MangaNotesScreen({
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
    final saved = useRef(false);
    final leaving = useRef(false);

    Future<bool> save() async {
      if (saved.value) return true;
      final ok = await persistMangaNotes(
        client: ref.read(graphQlClientProvider),
        mangaId: mangaId,
        rawText: controller.text,
        existingMetas: existingMetas,
        onSaved: () {
          if (context.mounted) refreshMangaAfterNotes(ref, mangaId);
        },
      );
      saved.value = ok;
      if (!ok && context.mounted) {
        ref
            .read(toastProvider)
            ?.showError(context.l10n.errorSomethingWentWrong);
      }
      return ok;
    }

    Future<void> leave() async {
      if (leaving.value) return;
      leaving.value = true;
      final ok = await save();
      leaving.value = false;
      if (ok && context.mounted) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: leave,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.editNotes),
              Text(
                seriesTitle,
                style: context.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: context.l10n.notes,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: MangaNotesFormatToolbar(controller: controller),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text('${value.text.length}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
