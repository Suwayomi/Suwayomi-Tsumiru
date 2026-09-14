import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../domain/settings/settings.dart';
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
        SectionTitle(title: context.l10n.serverBindings),
        SettingsPropTile(
          title: context.l10n.ip,
          leading: const Icon(Icons.computer_rounded),
          type: SettingsPropType.textField(
            hintText: context.l10n.ipHintText,
            value: serverBindingDto.ip,
            onChanged: canManage ? repository.updateIpAddress : null,
          ),
          subtitle: serverBindingDto.ip,
        ),
        SettingsPropTile(
          title: context.l10n.serverPort,
          subtitle: serverBindingDto.port.toString(),
          leading: const Icon(Icons.dns_rounded),
          type: SettingsPropType.numberPicker(
            min: 0,
            max: 65535,
            value: serverBindingDto.port,
            onChanged: canManage ? repository.updatePort : null,
          ),
        ),
      ],
    );
  }
}
