import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/misc/app_utils.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../utils/webui_meta/webui_settings.dart';
import '../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../widgets/input_popup/settings_prop_tile.dart';
import '../search/settings_search_registry.dart';

class WebUiSwitchTile extends ConsumerWidget {
  const WebUiSwitchTile({
    super.key,
    required this.setting,
    required this.title,
  });
  final String setting;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsHighlightTarget(
    id: setting,
    child: SettingsPropTile(
      title: title,
      type: SettingsPropType.switchTile(
        value: ref.watch(webUiBoolProvider(setting)),
        onChanged: ref.watch(webUiSettingsProvider).hasValue
            ? (value) => AppUtils.guard(
                () => ref
                    .read(webUiSettingsProvider.notifier)
                    .write(setting, encodeWebUiBool(value)),
                ref.read(toastProvider),
              )
            : null,
      ),
    ),
  );
}
