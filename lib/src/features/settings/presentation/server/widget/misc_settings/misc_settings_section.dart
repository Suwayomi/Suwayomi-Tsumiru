import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../controller/server_controller.dart';
import '../../../../domain/settings/settings.dart';
import '../../../../search/settings_search_registry.dart';
import '../../data/server_settings_repository.dart';
import 'data/misc_logs_repository.dart';
import 'graphql/__generated__/misc_logs.graphql.dart';

final _logSizePattern = RegExp(r'^[0-9]+(|kb|KB|mb|MB|gb|GB)$');

/// WebUI's log-size check (`ServerSettings.tsx`): digits with an optional
/// kb/mb/gb suffix. Anything else is rejected before anything is sent.
bool isValidLogSize(String value) => _logSizePattern.hasMatch(value);

class _LogSizeDialog extends HookWidget {
  const _LogSizeDialog({
    required this.title,
    required this.description,
    required this.value,
  });

  final String title;
  final String description;
  final String value;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: value);
    final error = useState<String?>(null);
    return AlertDialog(
      title: Text(title, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const Gap(16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: error.value,
            ),
            onChanged: (_) {
              if (error.value != null) error.value = null;
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () {
            if (!isValidLogSize(controller.text)) {
              error.value = context.l10n.invalidProp(title);
              return;
            }
            Navigator.pop(context, controller.text);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

class MiscSettingsSection extends ConsumerWidget {
  const MiscSettingsSection({super.key, required this.miscSettingsDto});
  final MiscSettingsDto miscSettingsDto;
  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(serverSettingsRepositoryProvider);
    final logsRepository = ref.watch(miscLogsRepositoryProvider);
    final logs = ref.watch(miscLogsSettingsProvider).value;
    Future<void> save(
      Future<Fragment$MiscLogsSettingsDto?> Function() action,
    ) async {
      final result = await AppUtils.guard(action, ref.read(toastProvider));
      if (result != null && context.mounted) {
        ref.invalidate(miscLogsSettingsProvider);
      }
    }

    Future<void> editLogSize({
      required String title,
      required String current,
      required Input$PartialSettingsTypeInput Function(String) patch,
    }) async {
      final next = await showDialog<String>(
        context: context,
        builder: (dialogContext) => _LogSizeDialog(
          title: title,
          description: dialogContext.l10n.logSizeExamples,
          value: current,
        ),
        animationStyle: context.motionStyle,
      );
      if (next == null || !context.mounted) return;
      await save(() => logsRepository.write(patch(next)));
    }

    SettingsHighlightTarget logSizeRow({
      required String id,
      required String title,
      required String current,
      required Input$PartialSettingsTypeInput Function(String) patch,
    }) => SettingsHighlightTarget(
      id: id,
      // Same merge guard as the OPDS rows: without it the engine folds
      // this row into the neighbouring switch row.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: ListTile(
          title: Text(title),
          subtitle: Text(current),
          onTap: canManage
              ? () => editLogSize(
                  title: title,
                  current: current,
                  patch: patch,
                )
              : null,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.misc),
        SettingsHighlightTarget(
          id: 'debugLogs',
          child: SwitchListTile(
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
        ),
        SettingsHighlightTarget(
          id: 'systemTrayIcon',
          child: SwitchListTile(
            title: Text(context.l10n.systemTrayIcon),
            subtitle: Text(context.l10n.systemTrayIconDescription),
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
        ),
        if (logs != null) ...[
          SettingsHighlightTarget(
            id: 'logFileCleanup',
            // Same merge guard as the OPDS rows: without it the engine folds
            // this row into the neighbouring switch rows.
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: SettingsPropTile(
                title: context.l10n.logFileCleanup,
                subtitle: context.l10n.nDays(logs.maxLogFiles.compact()!),
                type: SettingsPropType.numberSlider(
                  min: 0,
                  max: 1000,
                  value: logs.maxLogFiles.clamp(0, 1000),
                  onChanged: canManage
                      ? (value) => save(
                          () => logsRepository.write(
                            Input$PartialSettingsTypeInput(maxLogFiles: value),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          logSizeRow(
            id: 'maxLogFileSize',
            title: context.l10n.maxLogFileSize,
            current: logs.maxLogFileSize,
            patch: (value) =>
                Input$PartialSettingsTypeInput(maxLogFileSize: value),
          ),
          logSizeRow(
            id: 'maxLogFolderSize',
            title: context.l10n.maxLogFolderSize,
            current: logs.maxLogFolderSize,
            patch: (value) =>
                Input$PartialSettingsTypeInput(maxLogFolderSize: value),
          ),
        ],
      ],
    );
  }
}
