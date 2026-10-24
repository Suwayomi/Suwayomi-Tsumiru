import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/multi_select_popup.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import 'data/syncyomi_settings_provider.dart';
import 'data/syncyomi_settings_repository.dart';
import 'domain/sync_yomi.dart';
import 'syncyomi_sync.dart';
import 'widgets/sync_yomi_host_dialog.dart';

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

String syncYomiDataSummary(BuildContext context, List<SyncYomiDataKind> kinds) {
  if (kinds.isEmpty) return context.l10n.syncYomiSyncDataNone;
  return context.l10n.syncYomiSyncDataInclude(
    kinds.map((kind) => _syncYomiDataLabel(context, kind)).join(', '),
  );
}

class SyncYomiSettingsScreen extends ConsumerWidget {
  const SyncYomiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final topBar = showsMergedTopBar(context);
    final title = Text(l10n.syncyomi);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: SettingsHighlightScope(
        child: SingleChildScrollView(
          padding: settingsPagePadding(context),
          child: const SyncYomiSettingsBody(),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}

class SyncYomiSettingsBody extends ConsumerWidget {
  const SyncYomiSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref.watch(syncYomiSettingsProvider).showUiWhenData(
      context,
      skipLoadingOnReload: true,
      (settings) {
        if (settings == null) {
          return Emoticons(title: l10n.syncYomiUnsupported);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsGroupHeading(label: l10n.syncyomi, first: true),
            _SyncYomiFields(settings: settings),
            const SizedBox(height: 16),
            SettingsGroupCard(
              children: [
                _SyncNowSection(
                  canStart:
                      settings.enabled &&
                      settings.host.isNotBlank &&
                      settings.apiKey.isNotBlank,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SyncYomiFields extends ConsumerWidget {
  const _SyncYomiFields({required this.settings});

  final SyncYomiSettings settings;

  Future<bool> _save(WidgetRef ref, Future<bool> Function() request) async =>
      await AppUtils.guard(request, ref.read(toastProvider)) ?? false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repository = ref.watch(syncyomiSettingsRepositoryProvider);
    final intervalOption = syncYomiIntervalOption(settings.interval);
    final syncData = enabledSyncYomiData(
      manga: settings.dataManga,
      chapters: settings.dataChapters,
      categories: settings.dataCategories,
      history: settings.dataHistory,
      tracking: settings.dataTracking,
    );
    return SettingsGroupCard(
      children: [
        SettingsHighlightTarget(
          id: 'syncYomiEnabled',
          child: SettingsPropTile(
            title: l10n.syncYomiEnabled,
            type: SettingsPropType.switchTile(
              value: settings.enabled,
              onChanged: repository.updateEnabled,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'syncYomiHost',
          child: ListTile(
            title: Text(l10n.syncYomiHost),
            subtitle: Text(
              settings.host.isBlank ? l10n.syncYomiNotSet : settings.host,
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => SyncYomiHostDialog(
                value: settings.host,
                onSave: (host) => _save(ref, () => repository.updateHost(host)),
              ),
              animationStyle: context.motionStyle,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'syncYomiApiKey',
          child: SettingsPropTile(
            title: l10n.syncYomiApiKey,
            subtitle: settings.apiKey.isBlank
                ? l10n.syncYomiNotSet
                : l10n.syncYomiSet,
            type: SettingsPropType.textField(
              hintText: l10n.syncYomiApiKey,
              value: settings.apiKey,
              canObscure: true,
              onChanged: repository.updateApiKey,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'syncYomiSyncInterval',
          child: ListTile(
            title: Text(l10n.syncYomiSyncInterval),
            subtitle: Text(syncYomiIntervalLabel(context, settings.interval)),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => RadioListPopup<String>(
                title: l10n.syncYomiSyncInterval,
                optionList: [
                  ...kSyncYomiIntervalOptions,
                  if (intervalOption == null) settings.interval,
                ],
                getOptionTitle: (value) =>
                    syncYomiIntervalLabel(context, value),
                value: intervalOption ?? settings.interval,
                onChange: (value) {
                  _save(ref, () => repository.updateInterval(value));
                  Navigator.pop(context);
                },
              ),
              animationStyle: context.motionStyle,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'syncYomiSyncData',
          child: ListTile(
            title: Text(l10n.syncYomiSyncData),
            subtitle: Text(syncYomiDataSummary(context, syncData)),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => MultiSelectPopup<SyncYomiDataKind>(
                title: l10n.syncYomiSyncData,
                optionList: SyncYomiDataKind.values,
                values: syncData,
                getOptionTitle: (kind) => _syncYomiDataLabel(context, kind),
                onChange: (selected) {
                  _save(
                    ref,
                    () => repository.updateSyncData(
                      manga: selected.contains(SyncYomiDataKind.manga),
                      chapters: selected.contains(SyncYomiDataKind.chapters),
                      categories: selected.contains(
                        SyncYomiDataKind.categories,
                      ),
                      history: selected.contains(SyncYomiDataKind.history),
                      tracking: selected.contains(SyncYomiDataKind.tracking),
                    ),
                  );
                  Navigator.pop(context);
                },
              ),
              animationStyle: context.motionStyle,
            ),
          ),
        ),
      ],
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
        SettingsHighlightTarget(
          id: 'syncYomiSyncNow',
          child: ListTile(
            enabled: canStart,
            leading: const Icon(Icons.sync_rounded),
            title: Text(l10n.syncYomiSyncNow),
            onTap: canStart ? sync.start : null,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          child: statusLine,
        ),
      ],
    );
  }
}
