import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/multi_select_popup.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../account/data/account_providers.dart';
import '../../../account/domain/account_access.dart';
import '../../controller/server_controller.dart';
import '../../data/user_settings.dart';
import '../../domain/settings/settings.dart';
import 'data/syncyomi_settings_repository.dart';
import 'domain/sync_yomi.dart';
import 'syncyomi_sync.dart';
import 'widgets/sync_yomi_host_dialog.dart';

/// Wording for a stored interval. Values the picker doesn't offer come from
/// another client, so they are read out as hours or minutes instead.
String syncYomiIntervalLabel(BuildContext context, String value) {
  final description = describeSyncYomiInterval(value);
  final l10n = context.l10n;
  return switch (description.label) {
    SyncYomiIntervalLabel.manualOnly => l10n.offlineManualOnly,
    SyncYomiIntervalLabel.every30Minutes => l10n.syncYomiEvery30Minutes,
    SyncYomiIntervalLabel.everyHour => l10n.syncYomiEveryHour,
    SyncYomiIntervalLabel.every3Hours => l10n.syncYomiEvery3Hours,
    SyncYomiIntervalLabel.every6Hours => l10n.syncYomiEvery6Hours,
    SyncYomiIntervalLabel.every12Hours => l10n.syncYomiEvery12Hours,
    SyncYomiIntervalLabel.daily => l10n.syncYomiDaily,
    SyncYomiIntervalLabel.weekly => l10n.syncYomiWeekly,
    SyncYomiIntervalLabel.everyNHours => l10n.syncYomiEveryNHours(
      description.count,
    ),
    SyncYomiIntervalLabel.everyNMinutes => l10n.syncYomiEveryNMinutes(
      description.count,
    ),
    SyncYomiIntervalLabel.verbatim => description.raw ?? value,
  };
}

String _syncYomiDataLabel(BuildContext context, SyncYomiDataKind kind) {
  final l10n = context.l10n;
  return switch (kind) {
    SyncYomiDataKind.manga => l10n.syncYomiSyncDataManga,
    SyncYomiDataKind.chapters => l10n.syncYomiSyncDataChapters,
    SyncYomiDataKind.categories => l10n.syncYomiSyncDataCategories,
    SyncYomiDataKind.history => l10n.syncYomiSyncDataHistory,
    SyncYomiDataKind.tracking => l10n.syncYomiSyncDataTracking,
  };
}

/// The Sync data subtitle: what a sync will carry, or that it carries nothing.
String syncYomiDataSummary(BuildContext context, List<SyncYomiDataKind> kinds) {
  if (kinds.isEmpty) return context.l10n.syncYomiSyncDataNone;
  return context.l10n.syncYomiSyncDataInclude(
    kinds.map((kind) => _syncYomiDataLabel(context, kind)).join(', '),
  );
}

class SyncYomiSettingsScreen extends ConsumerWidget {
  const SyncYomiSettingsScreen({super.key});

  Future<bool> _save(
    WidgetRef ref,
    Future<SettingsDto?> Function() request,
  ) async {
    final result = await AppUtils.guard(request, ref.read(toastProvider));
    if (result == null) return false;
    ref.read(settingsProvider.notifier).updateState(result);
    return true;
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
        final intervalOption = syncYomiIntervalOption(settings.syncInterval);
        final syncData = enabledSyncYomiData(
          manga: settings.syncDataManga,
          chapters: settings.syncDataChapters,
          categories: settings.syncDataCategories,
          history: settings.syncDataHistory,
          tracking: settings.syncDataTracking,
        );
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
                        // Matched on duration, so P1D reads as the PT24H option
                        // rather than being offered as a second "Daily" row.
                        optionList: [
                          ...kSyncYomiIntervalOptions,
                          if (intervalOption == null) settings.syncInterval,
                        ],
                        getOptionTitle: (value) =>
                            syncYomiIntervalLabel(context, value),
                        value: intervalOption ?? settings.syncInterval,
                        onChange: (value) {
                          _save(ref, () => repository.updateInterval(value));
                          Navigator.pop(context);
                        },
                      ),
                    )
                  : null,
            ),
            ListTile(
              enabled: canEdit,
              title: Text(l10n.syncYomiSyncData),
              subtitle: Text(syncYomiDataSummary(context, syncData)),
              onTap: canEdit
                  ? () => showDialog<void>(
                      context: context,
                      builder: (context) => MultiSelectPopup<SyncYomiDataKind>(
                        title: l10n.syncYomiSyncData,
                        optionList: SyncYomiDataKind.values,
                        values: syncData,
                        getOptionTitle: (kind) =>
                            _syncYomiDataLabel(context, kind),
                        onChange: (selected) {
                          _save(
                            ref,
                            () => repository.updateSyncData(
                              manga: selected.contains(SyncYomiDataKind.manga),
                              chapters: selected.contains(
                                SyncYomiDataKind.chapters,
                              ),
                              categories: selected.contains(
                                SyncYomiDataKind.categories,
                              ),
                              history: selected.contains(
                                SyncYomiDataKind.history,
                              ),
                              tracking: selected.contains(
                                SyncYomiDataKind.tracking,
                              ),
                            ),
                          );
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
    final sync = useSyncYomi(ref);
    final view = sync.view;
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
          Text(
            l10n.syncYomiSyncingStep(syncYomiStepName(context, sync.step)),
            style: textStyle,
          ),
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
          onTap: canStart ? sync.start : null,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          child: statusLine,
        ),
      ],
    );
  }
}
