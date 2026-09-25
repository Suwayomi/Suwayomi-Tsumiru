import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/domain/account_access.dart';
import '../../controller/server_controller.dart';
import '../../data/user_settings.dart';
import '../../domain/settings/settings.dart';
import 'data/syncyomi_settings_repository.dart';
import 'domain/sync_yomi.dart';
import 'widgets/sync_yomi_host_dialog.dart';

/// Wording for a stored interval. Values the picker doesn't offer come from
/// another client, so they are read out as hours or minutes instead.
String syncYomiIntervalLabel(BuildContext context, String value) {
  final description = describeSyncYomiInterval(value);
  final l10n = context.l10n;
  return switch (description.label) {
    SyncYomiIntervalLabel.manualOnly => l10n.offlineManualOnly,
    SyncYomiIntervalLabel.everyHour => l10n.syncYomiEveryHour,
    SyncYomiIntervalLabel.every6Hours => l10n.syncYomiEvery6Hours,
    SyncYomiIntervalLabel.every12Hours => l10n.syncYomiEvery12Hours,
    SyncYomiIntervalLabel.everyDay => l10n.syncYomiEveryDay,
    SyncYomiIntervalLabel.everyNHours => l10n.syncYomiEveryNHours(
      description.count,
    ),
    SyncYomiIntervalLabel.everyNMinutes => l10n.syncYomiEveryNMinutes(
      description.count,
    ),
    SyncYomiIntervalLabel.verbatim => description.raw ?? value,
  };
}

class SyncYomiSettingsScreen extends ConsumerWidget {
  const SyncYomiSettingsScreen({super.key});

  Future<void> _save(
    WidgetRef ref,
    Future<SettingsDto?> Function() request,
  ) async {
    final result = await AppUtils.guard(request, ref.read(toastProvider));
    if (result != null) ref.read(settingsProvider.notifier).updateState(result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repository = ref.watch(syncyomiSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final personalSettings = ref.watch(personalSettingsProvider);
    final access = ref.watch(settledAccountAccessProvider);
    final canEdit =
        access.capability != AccountCapability.unknown &&
        !personalSettings.isLoading &&
        !personalSettings.hasError &&
        personalSettings.value != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncyomi)),
      body: serverSettings.showUiWhenData(context, (data) {
        final settings = canEdit ? personalSettings.value : data;
        if (settings == null) {
          return Emoticons(title: l10n.noPropFound(l10n.syncyomi));
        }
        return ListView(
          children: [
            SettingsPropTile(
              title: l10n.syncYomiEnabled,
              type: SettingsPropType.switchTile(
                value: settings.syncYomiEnabled,
                onChanged: canEdit ? repository.updateEnabled : null,
              ),
            ),
            ListTile(
              enabled: canEdit,
              title: Text(l10n.syncYomiHost),
              subtitle: Text(
                settings.syncYomiHost.isBlank
                    ? l10n.syncYomiNotSet
                    : settings.syncYomiHost,
              ),
              onTap: canEdit
                  ? () => showDialog<void>(
                      context: context,
                      builder: (_) => SyncYomiHostDialog(
                        value: settings.syncYomiHost,
                        onSave: (host) =>
                            _save(ref, () => repository.updateHost(host)),
                      ),
                    )
                  : null,
            ),
            SettingsPropTile(
              title: l10n.syncYomiApiKey,
              subtitle: settings.syncYomiApiKey.isBlank
                  ? l10n.syncYomiNotSet
                  : l10n.syncYomiSet,
              type: SettingsPropType.textField(
                hintText: l10n.syncYomiApiKey,
                value: settings.syncYomiApiKey,
                canObscure: true,
                onChanged: canEdit ? repository.updateApiKey : null,
              ),
            ),
            ListTile(
              enabled: canEdit,
              title: Text(l10n.syncYomiSyncInterval),
              subtitle: Text(
                syncYomiIntervalLabel(context, settings.syncInterval),
              ),
              onTap: canEdit
                  ? () => showDialog<void>(
                      context: context,
                      builder: (context) => RadioListPopup<String>(
                        title: l10n.syncYomiSyncInterval,
                        optionList: [
                          ...kSyncYomiIntervalOptions,
                          if (!kSyncYomiIntervalOptions.contains(
                            settings.syncInterval,
                          ))
                            settings.syncInterval,
                        ],
                        getOptionTitle: (value) =>
                            syncYomiIntervalLabel(context, value),
                        value: settings.syncInterval,
                        onChange: (value) {
                          _save(ref, () => repository.updateInterval(value));
                          Navigator.pop(context);
                        },
                      ),
                    )
                  : null,
            ),
            _SyncNowSection(
              canStart:
                  canEdit &&
                  settings.syncYomiEnabled &&
                  settings.syncYomiHost.isNotBlank &&
                  settings.syncYomiApiKey.isNotBlank,
            ),
          ],
        );
      }),
    );
  }
}

class _SyncNowSection extends HookConsumerWidget {
  const _SyncNowSection({required this.canStart});

  final bool canStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repository = ref.watch(syncyomiSettingsRepositoryProvider);
    final status = ref.watch(lastSyncStatusProvider);
    final requested = useState(false);
    final view = syncYomiStatusView(
      state: status.value?.state.name,
      endDate: status.value?.endDate,
      errorMessage: status.value?.errorMessage,
    );
    final terminal =
        view.kind == SyncYomiStatusKind.synced ||
        view.kind == SyncYomiStatusKind.failed;
    final poll =
        !terminal &&
        (requested.value || view.kind == SyncYomiStatusKind.syncing);

    // Poll only while a sync is actually in flight, capped at ten minutes.
    useEffect(() {
      if (!poll) return null;
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      final timer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (DateTime.now().isAfter(deadline)) {
          timer.cancel();
          return;
        }
        ref.invalidate(lastSyncStatusProvider);
      });
      return timer.cancel;
    }, [poll]);

    Future<void> startSync() async {
      final result = await AppUtils.guard(
        repository.startSync,
        ref.read(toastProvider),
      );
      if (!context.mounted || result == null) return;
      final toast = ref.read(toastProvider);
      switch (result) {
        case Enum$StartSyncResult.SUCCESS:
          toast?.show(l10n.syncYomiSyncStarted);
          requested.value = true;
        case Enum$StartSyncResult.SYNC_IN_PROGRESS:
          toast?.show(l10n.syncYomiAlreadyRunning);
          requested.value = true;
        case Enum$StartSyncResult.SYNC_DISABLED:
          toast?.show(l10n.syncYomiDisabled);
        case Enum$StartSyncResult.$unknown:
          break;
      }
      if (requested.value) ref.invalidate(lastSyncStatusProvider);
    }

    final textStyle = context.theme.textTheme.bodyMedium?.copyWith(
      color: context.theme.hintColor,
    );
    final Widget statusLine = switch (view.kind) {
      SyncYomiStatusKind.never => Text(
        l10n.syncYomiNeverSynced,
        style: textStyle,
      ),
      SyncYomiStatusKind.synced => Text(
        view.endDate == null
            ? l10n.syncYomiNeverSynced
            : l10n.syncYomiLastSynced(
                DateFormat.yMd(
                  l10n.localeName,
                ).add_jms().format(view.endDate!.toLocal()),
              ),
        style: textStyle,
      ),
      SyncYomiStatusKind.failed => Text(
        l10n.syncYomiLastSyncFailed(
          view.error.ifBlank(l10n.syncYomiUnknownError),
        ),
        style: textStyle?.copyWith(color: context.theme.colorScheme.error),
      ),
      SyncYomiStatusKind.syncing => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const Gap(8),
          Text(l10n.syncYomiSyncing, style: textStyle),
        ],
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          enabled: canStart,
          leading: const Icon(Icons.sync_rounded),
          title: Text(l10n.syncYomiSyncNow),
          onTap: canStart ? startSync : null,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          child: statusLine,
        ),
      ],
    );
  }
}
