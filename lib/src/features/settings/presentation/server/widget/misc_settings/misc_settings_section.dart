import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../controller/server_controller.dart';
import '../../../../domain/settings/settings.dart';
import '../../data/server_settings_repository.dart';

class MiscSettingsSection extends ConsumerWidget {
  const MiscSettingsSection({super.key, required this.miscSettingsDto});
  final MiscSettingsDto miscSettingsDto;
  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(serverSettingsRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.misc),
        SwitchListTile(
          title: Text(context.l10n.debugLogs),
          value: miscSettingsDto.debugLogsEnabled,
          onChanged: canManage
              ? (isEnabled) async {
                  final value = await AppUtils.guard(
                    () => repository.toggleDebugLogs(isEnabled),
                    ref.read(toastProvider),
                  );
                  if (value != null && context.mounted) {
                    ref.read(settingsProvider.notifier).updateState(value);
                  }
                }
              : null,
        ),
        SwitchListTile(
          title: Text(context.l10n.systemTrayIcon),
          subtitle: Text(context.l10n.systemTrayIcon),
          value: miscSettingsDto.systemTrayEnabled,
          onChanged: canManage
              ? (isEnabled) async {
                  final value = await AppUtils.guard(
                    () => repository.toggleSystemTrayEnabled(isEnabled),
                    ref.read(toastProvider),
                  );
                  if (value != null && context.mounted) {
                    ref.read(settingsProvider.notifier).updateState(value);
                  }
                }
              : null,
        ),
      ],
    );
  }
}
