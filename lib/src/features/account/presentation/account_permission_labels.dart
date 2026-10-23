import 'package:flutter/material.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';

Map<Enum$UserPermission, String> accountPermissionLabels(
  BuildContext context,
) => {
  Enum$UserPermission.INSTALL_EXTENSIONS:
      context.l10n.accountPermissionInstallExtensions,
  Enum$UserPermission.INSTALL_EXTERNAL_EXTENSIONS:
      context.l10n.accountPermissionInstallExternalExtensions,
  Enum$UserPermission.UNINSTALL_EXTENSIONS:
      context.l10n.accountPermissionUninstallExtensions,
  Enum$UserPermission.DOWNLOAD_CHAPTERS:
      context.l10n.accountPermissionDownloadChapters,
  Enum$UserPermission.MANAGE_SETTINGS:
      context.l10n.accountPermissionManageSettings,
  Enum$UserPermission.MANAGE_USERS: context.l10n.accountPermissionManageUsers,
  Enum$UserPermission.MANAGE_EXTENSION_STORES:
      context.l10n.accountPermissionManageExtensionStores,
  Enum$UserPermission.MANAGE_SOURCE_PREFERENCES:
      context.l10n.accountPermissionManageSourcePreferences,
  Enum$UserPermission.MANAGE_CACHE: context.l10n.accountPermissionManageCache,
};

class AccountPermissionPicker extends StatelessWidget {
  const AccountPermissionPicker({
    super.key,
    required this.permissions,
    this.onChanged,
  });

  final Set<Enum$UserPermission> permissions;
  final ValueChanged<Set<Enum$UserPermission>>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final entry in accountPermissionLabels(context).entries)
        SwitchListTile(
          dense: true,
          title: Text(entry.value),
          value: permissions.contains(entry.key),
          onChanged: onChanged == null
              ? null
              : (allowed) {
                  final updated = {...permissions};
                  if (allowed) {
                    updated.add(entry.key);
                  } else {
                    updated.remove(entry.key);
                  }
                  onChanged!(updated);
                },
        ),
    ],
  );
}
