import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/timeout_constants.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../widgets/compact_switch.dart';
import '../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../search/settings_search_registry.dart';
import '../../../widgets/settings_group_card/settings_group_card.dart';

part 'timeout_settings_section.g.dart';

@riverpod
class ServerRequestTimeout extends _$ServerRequestTimeout
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(
    DBKeys.serverRequestTimeout,
    initial: DBKeys.serverRequestTimeout.initial,
  );

  void updateSeconds(int seconds) => update(seconds * 1000);
}

@riverpod
class AutoRefreshOnTimeout extends _$AutoRefreshOnTimeout
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
    DBKeys.autoRefreshOnTimeout,
    initial: DBKeys.autoRefreshOnTimeout.initial,
  );
}

@riverpod
class AutoRefreshRetryDelay extends _$AutoRefreshRetryDelay
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(
    DBKeys.autoRefreshRetryDelay,
    initial: DBKeys.autoRefreshRetryDelay.initial,
  );

  void updateSeconds(int seconds) => update(seconds * 1000);
}

class TimeoutSettingsSection extends ConsumerWidget {
  const TimeoutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeoutMs = ref
        .watch(serverRequestTimeoutProvider)
        .ifNull(TimeoutConstants.requestTimeoutDefaultMs);
    final autoRefreshEnabled = ref.watch(autoRefreshOnTimeoutProvider).ifNull();
    final retryDelayMs = ref
        .watch(autoRefreshRetryDelayProvider)
        .ifNull(TimeoutConstants.autoRefreshRetryDelayDefaultMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.timeouts),
        SettingsGroupCard(
          children: [
            SettingsHighlightTarget(
              id: 'serverRequestTimeout',
              child: SettingsPropTile(
                title: context.l10n.serverRequestTimeout,
                subtitle: context.l10n.nSeconds((timeoutMs / 1000).round()),
                type: SettingsPropType.numberSlider(
                  min: TimeoutConstants.requestTimeoutMinSeconds,
                  max: TimeoutConstants.requestTimeoutMaxSeconds,
                  value: (timeoutMs / 1000).round(),
                  onChanged: (seconds) async {
                    ref
                        .read(serverRequestTimeoutProvider.notifier)
                        .update(seconds * 1000);
                  },
                ),
              ),
            ),
            SettingsHighlightTarget(
              id: 'autoRefreshOnTimeout',
              child: CompactSwitchListTile(
                controlAffinity: ListTileControlAffinity.trailing,
                title: Text(context.l10n.autoRefreshOnTimeout),
                subtitle: Text(context.l10n.autoRefreshOnTimeoutDescription),
                value: autoRefreshEnabled,
                onChanged: ref
                    .read(autoRefreshOnTimeoutProvider.notifier)
                    .update,
              ),
            ),
            if (autoRefreshEnabled)
              SettingsHighlightTarget(
                id: 'autoRefreshRetryDelay',
                child: SettingsPropTile(
                  title: context.l10n.autoRefreshRetryDelay,
                  subtitle: context.l10n.nSeconds(
                    (retryDelayMs / 1000).round(),
                  ),
                  type: SettingsPropType.numberSlider(
                    min: TimeoutConstants.autoRefreshRetryDelayMinSeconds,
                    max: TimeoutConstants.autoRefreshRetryDelayMaxSeconds,
                    value: (retryDelayMs / 1000).round(),
                    onChanged: (seconds) async {
                      ref
                          .read(autoRefreshRetryDelayProvider.notifier)
                          .update(seconds * 1000);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
