import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/endpoints.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/file_picker_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../domain/settings/settings.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../server/widget/client/server_url_tile/server_url_tile.dart';
import '../../data/backup_settings_repository.dart';
import '../backup_flags/backup_flags_dialog.dart';
import 'widgets/backup_missing_dialog.dart';
import 'widgets/restore_status_progress.dart';

class BackupAndRestoreSection extends HookConsumerWidget {
  const BackupAndRestoreSection({super.key});

  Future<void> createBackupFile(WidgetRef ref, BuildContext context) async {
    final flags = await showBackupFlagsDialog(
      context,
      title: context.l10n.createBackup,
    );
    if (flags == null || !context.mounted) return;
    final toast = ref.read(toastProvider);
    final backupUrl = await AsyncValue.guard(
      () => ref.read(backupSettingsRepositoryProvider).createBackup(flags),
    );
    if (!context.mounted) return;
    if (backupUrl.hasError || backupUrl.value.isBlank) {
      toast?.showError(
        backupUrl.error?.toString() ?? context.l10n.errorBackupCreate,
      );
      return;
    }
    launchUrlInWeb(
      context,
      Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider),
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            appendApiToUrl: false,
          ) +
          backupUrl.value!,
      toast,
    );
  }

  Future<PlatformFile?> getBackupFile(
    BuildContext context,
    Toast? toast,
  ) async {
    final asyncPickedFile = await AsyncValue.guard(
      () => FilePickerUtils.pickFile(
        context: context,
        extensions: ['gz', 'tachibk'],
      ),
    );
    if (!context.mounted) {
      return null;
    }
    if (asyncPickedFile.hasError || asyncPickedFile.value == null) {
      toast?.showError(
        asyncPickedFile.error?.toString() ?? context.l10n.errorFilePick,
      );
      return null;
    }
    return asyncPickedFile.value;
  }

  Future<String?> backupFilePicker(WidgetRef ref, BuildContext context) async {
    Toast? toast = ref.read(toastProvider);

    final pickedFile = await getBackupFile(context, toast);
    if (pickedFile == null) return null;

    final asyncBackupFile = await AsyncValue.guard(
      () => FilePickerUtils.convertToMultipartFile(pickedFile, "backup"),
    );

    if (asyncBackupFile.hasError || asyncBackupFile.value == null) {
      // Bail unconditionally — mounted only gates the toast, not the null-assertion below.
      if (context.mounted) asyncBackupFile.showToastOnError(toast);
      return null;
    }

    final backupFile = asyncBackupFile.value!;
    if (context.mounted) toast?.show(context.l10n.validating);

    final validateResult = await AsyncValue.guard(
      () =>
          ref.read(backupSettingsRepositoryProvider).validateBackup(backupFile),
    );

    if (validateResult.hasError) {
      // Bail unconditionally — don't let an unmounted validation failure proceed to restore.
      if (context.mounted) validateResult.showToastOnError(toast);
      return null;
    }

    String? backupId;
    bool restoreBackup = true;
    if (validateResult.value.isNotBlank) {
      // Can't confirm missing sources without a context to show the dialog in.
      if (!context.mounted) return null;
      restoreBackup = (await showDialog<bool>(
        context: context,
        builder: (context) =>
            BackupMissingDialog(backupMissing: validateResult.value!),
        animationStyle: context.motionStyle,
      )).ifNull();
    }

    if (restoreBackup) {
      // Can't pick flags without a context to show the dialog in.
      if (!context.mounted) return null;
      final flags = await showBackupFlagsDialog(
        context,
        title: context.l10n.restoreBackupTitle,
      );
      if (flags == null || !context.mounted) return null;
      final asyncBackupFile = await AsyncValue.guard(
        () => FilePickerUtils.convertToMultipartFile(pickedFile, "backup"),
      );

      if (asyncBackupFile.hasError || asyncBackupFile.value == null) {
        // Same unconditional bail as the first conversion.
        if (context.mounted) asyncBackupFile.showToastOnError(toast);
        return null;
      }
      final backupResponse = (await AsyncValue.guard(
        () => ref
            .read(backupSettingsRepositoryProvider)
            .restoreBackup(asyncBackupFile.value!, flags),
      ));

      if (backupResponse.hasError) {
        toast?.showError(backupResponse.error.toString());
      } else {
        if (backupResponse.hasValue) {
          backupId = backupResponse.value;
        }
        if (context.mounted) {
          toast?.show(context.l10n.restoring, instantShow: true);
        }
      }
    }
    return backupId;
  }

  @override
  Widget build(context, ref) {
    final restoreId = useState<String?>(null);
    final toast = ref.watch(toastProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.backupAndRestore),
        SettingsHighlightTarget(
          id: 'createBackup',
          child: ListTile(
            title: Text(context.l10n.createBackupTitle),
            subtitle: Text(context.l10n.createBackupDescription),
            leading: const Icon(Icons.backup_rounded),
            onTap: () => createBackupFile(ref, context),
          ),
        ),
        SettingsHighlightTarget(
          id: 'restoreBackup',
          child: ListTile(
            title: Text(context.l10n.restoreBackupTitle),
            subtitle: Text(context.l10n.restoreBackupDescription),
            leading: const Icon(Icons.restore_rounded),
            trailing: restoreId.value != null
                ? RestoreStatusProgress(
                    restoreRequestId: restoreId.value!,
                    onCompleted: (state) {
                      if (state == RestoreState.FAILURE) {
                        toast?.showError(
                          context.l10n.errorBackupRestore,
                          withMicrotask: true,
                        );
                      } else {
                        toast?.show(
                          context.l10n.restored,
                          withMicrotask: true,
                          instantShow: true,
                        );
                      }
                      restoreId.value = null;
                    },
                  )
                : null,
            onTap: () async =>
                restoreId.value = await backupFilePicker(ref, context),
          ),
        ),
        const Gap(8),
      ],
    );
  }
}
