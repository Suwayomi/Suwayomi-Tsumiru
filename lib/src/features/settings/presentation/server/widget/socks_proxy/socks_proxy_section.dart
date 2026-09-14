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

class SocksProxySection extends ConsumerWidget {
  const SocksProxySection({super.key, required this.socksProxyDto});
  final SocksProxyDto socksProxyDto;
  @override
  Widget build(context, ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(serverSettingsRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.socksProxy),
        SettingsPropTile(
          title: context.l10n.enableSocksProxy,
          type: SettingsPropType<SettingsDto>.switchTile(
            value: socksProxyDto.socksProxyEnabled,
            onChanged: canManage ? repository.toggleSocksProxy : null,
          ),
        ),
        if (socksProxyDto.socksProxyEnabled) ...[
          SettingsPropTile(
            title: context.l10n.socksVersion,
            subtitle: socksProxyDto.socksProxyVersion.toString(),
            type: SettingsPropType.numberPicker(
              min: 4,
              max: 5,
              value: socksProxyDto.socksProxyVersion,
              onChanged: canManage ? repository.updateSocksVersion : null,
            ),
          ),
          SettingsPropTile(
            title: context.l10n.socksHost,
            type: SettingsPropType.textField(
              hintText: context.l10n.enterProp(context.l10n.socksHost),
              value: socksProxyDto.socksProxyHost,
              onChanged: canManage ? repository.updateSocksHost : null,
            ),
            subtitle: socksProxyDto.socksProxyHost,
          ),
          SettingsPropTile(
            title: context.l10n.socksPort,
            subtitle: socksProxyDto.socksProxyPort.toString(),
            type: SettingsPropType.numberPicker(
              min: 0,
              max: 65535,
              value: int.tryParse(socksProxyDto.socksProxyPort),
              onChanged: canManage
                  ? (port) async => repository.updateSocksPort(port.toString())
                  : null,
            ),
          ),
          SettingsPropTile(
            title: context.l10n.socksUserName,
            type: SettingsPropType.textField(
              hintText: context.l10n.enterProp(context.l10n.socksUserName),
              value: socksProxyDto.socksProxyUsername,
              onChanged: canManage ? repository.updateSocksUserName : null,
            ),
            subtitle: socksProxyDto.socksProxyUsername,
          ),
          SettingsPropTile(
            title: context.l10n.socksPassword,
            type: SettingsPropType.textField(
              canObscure: true,
              hintText: context.l10n.enterProp(context.l10n.socksPassword),
              value: socksProxyDto.socksProxyPassword,
              onChanged: canManage ? repository.updateSocksPassword : null,
            ),
          ),
        ],
      ],
    );
  }
}
