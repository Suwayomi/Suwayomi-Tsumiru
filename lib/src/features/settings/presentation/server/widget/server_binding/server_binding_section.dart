import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../domain/settings/settings.dart';
import '../../../../search/settings_search_registry.dart';
import '../../../../widgets/settings_group_card/settings_group_card.dart';
import '../../data/server_settings_repository.dart';

class ServerBindingSection extends ConsumerWidget {
  const ServerBindingSection({super.key, required this.serverBindingDto});
  final ServerBindingDto serverBindingDto;
  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(serverSettingsRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeading(label: context.l10n.serverBindings, first: true),
        SettingsGroupCard(
          children: [
            SettingsHighlightTarget(
              id: 'serverIpAddress',
              child: SettingsPropTile(
                title: context.l10n.ip,
                type: SettingsPropType.textField(
                  hintText: context.l10n.ipHintText,
                  value: serverBindingDto.ip,
                  onChanged: canManage ? repository.updateIpAddress : null,
                ),
                subtitle: serverBindingDto.ip,
              ),
            ),
            SettingsHighlightTarget(
              id: 'serverPort',
              child: SettingsPropTile(
                title: context.l10n.serverPort,
                subtitle: serverBindingDto.port.toString(),
                type: SettingsPropType.numberPicker(
                  min: 0,
                  max: 65535,
                  value: serverBindingDto.port,
                  onChanged: canManage ? repository.updatePort : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
