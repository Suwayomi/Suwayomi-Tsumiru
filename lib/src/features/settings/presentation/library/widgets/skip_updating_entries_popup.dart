import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../../constants/app_sizes.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../controller/server_controller.dart';
import '../../../data/user_settings.dart';
import '../../../domain/settings/settings.dart';
import '../data/library_settings_repository.dart';

class SkipUpdatingEntriesPopup extends ConsumerWidget {
  const SkipUpdatingEntriesPopup({super.key});

  @override
  Widget build(context, ref) {
    final settingsDto = ref.watch(personalSettingsProvider);
    final canEdit =
        !settingsDto.isLoading &&
        !settingsDto.hasError &&
        settingsDto.value != null;
    final repository = ref.watch(librarySettingsRepositoryProvider);
    final LibrarySettingsDto? librarySettingsDto = settingsDto.value;
    return AlertDialog(
      title: Text(context.l10n.skipUpdatingEntries),
      contentPadding: KEdgeInsets.v8.size,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.theme.colorScheme.primary,
              title: Text(context.l10n.withCompletedStatus),
              value: librarySettingsDto?.excludeCompleted.ifNull(),
              onChanged: !canEdit
                  ? null
                  : (value) async {
                      final result = await AppUtils.guard(
                        () => repository.toggleExcludeCompleted(value.ifNull()),
                        ref.read(toastProvider),
                      );
                      if (result != null && context.mounted) {
                        ref.read(settingsProvider.notifier).updateState(result);
                      }
                    },
            ),
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.theme.colorScheme.primary,
              title: Text(context.l10n.thatHaventBeenStarted),
              value: librarySettingsDto?.excludeNotStarted.ifNull(),
              onChanged: !canEdit
                  ? null
                  : (value) async {
                      final result = await AppUtils.guard(
                        () =>
                            repository.toggleExcludeNotStarted(value.ifNull()),
                        ref.read(toastProvider),
                      );
                      if (result != null && context.mounted) {
                        ref.read(settingsProvider.notifier).updateState(result);
                      }
                    },
            ),
            CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.theme.colorScheme.primary,
              title: Text(context.l10n.withUnreadChapter),
              value: librarySettingsDto?.excludeUnreadChapters.ifNull(),
              onChanged: !canEdit
                  ? null
                  : (value) async {
                      final result = await AppUtils.guard(
                        () => repository.toggleExcludeUnreadChapters(
                          value.ifNull(),
                        ),
                        ref.read(toastProvider),
                      );
                      if (result != null && context.mounted) {
                        ref.read(settingsProvider.notifier).updateState(result);
                      }
                    },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
