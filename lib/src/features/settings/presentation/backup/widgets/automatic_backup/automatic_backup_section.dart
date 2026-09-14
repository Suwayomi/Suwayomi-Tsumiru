import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/emoticons.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../controller/server_controller.dart';
import '../../../../domain/settings/settings.dart';
import '../../data/backup_settings_repository.dart';

class AutomaticBackupSection extends ConsumerWidget {
  const AutomaticBackupSection({super.key});

  @override
  Widget build(context, ref) {
    final AsyncValue<AutomaticBackupSettingsDto?> automaticBackupSettings = ref
        .watch(settingsProvider);
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(backupSettingsRepositoryProvider);

    return automaticBackupSettings.showUiWhenData(context, (data) {
      if (data == null) {
        return Emoticons(title: context.l10n.errorSomethingWentWrong);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: context.l10n.automaticBackup),
          if (!canManage)
            ListTile(
              subtitle: Text(context.l10n.manageSettingsPermissionRequired),
            ),
          SettingsPropTile(
            title: context.l10n.socksHost,
            leading: const Icon(Icons.folder_rounded),
            subtitle: data.backupPath,
            description: context.l10n.backupLocationDescription,
            type: SettingsPropType.textField(
              hintText: context.l10n.enterProp(context.l10n.backupLocation),
              value: data.backupPath,
              onChanged: canManage ? repository.updateBackupLocation : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.access_alarm_rounded),
            title: Text(context.l10n.backupTime),
            subtitle: data.backupTime.toTimeOfDay != null
                ? Text(data.backupTime.toTimeOfDay!.format(context))
                : null,
            onTap: canManage
                ? () async {
                    final backupTime = await showTimePicker(
                      initialTime:
                          data.backupTime.toTimeOfDay ??
                          const TimeOfDay(hour: 0, minute: 0),
                      context: context,
                    );
                    if (backupTime != null) {
                      final result = await AppUtils.guard(
                        () => repository.updateBackupTime(backupTime),
                        ref.read(toastProvider),
                      );
                      if (result != null && context.mounted) {
                        ref.read(settingsProvider.notifier).updateState(result);
                      }
                    } else {
                      if (context.mounted) {
                        ref
                            .read(toastProvider)
                            ?.showError(
                              context.l10n.invalidProp(context.l10n.backupTime),
                            );
                      }
                    }
                  }
                : null,
          ),
          SettingsPropTile(
            leading: const Icon(Icons.folder_rounded),
            title: context.l10n.backupInterval,
            subtitle: context.l10n.nDays(
              data.backupInterval.ifNullOrZero(1).compact()!,
            ),
            type: SettingsPropType.numberSlider(
              min: 1,
              max: 31,
              value: data.backupInterval,
              onChanged: canManage ? repository.updateBackupInterval : null,
            ),
          ),
          SettingsPropTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: context.l10n.backupCleanup,
            subtitle: context.l10n.backupCleanupDescription(
              data.backupTTL.ifNull(14).compact()!,
            ),
            type: SettingsPropType.numberSlider(
              min: 0,
              max: 1000,
              value: data.backupTTL,
              onChanged: canManage ? repository.updateBackupTTL : null,
            ),
          ),
        ],
      );
    });
  }
}
