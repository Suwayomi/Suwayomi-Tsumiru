// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show ChapterMenuRow;
import '../../../domain/extension/extension_model.dart';
import '../../source/controller/source_controller.dart';
import '../controller/extension_actions.dart';
import 'extension_info_dialog.dart';

Future<void> showExtensionContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required Extension extension,
}) async {
  Future<void> guard(Future<void> Function(ExtensionActions actions) action) =>
      AppUtils.guard(
        () => action(ref.read(extensionActionsProvider)),
        ref.read(toastProvider),
      );

  Future<void> uninstall() async {
    if (!await confirmAction(
          context,
          title: context.l10n.uninstall,
          message: context.l10n.confirmUninstallMessage,
          action: context.l10n.uninstall,
        ) ||
        !context.mounted) {
      return;
    }
    await guard((actions) => actions.uninstall(extension.pkgName));
  }

  final access = ref.read(settledAccountAccessProvider);
  final canInstall = access.allows(Enum$UserPermission.INSTALL_EXTENSIONS);
  final canUninstall = access.allows(Enum$UserPermission.UNINSTALL_EXTENSIONS);
  final installed = extension.isInstalled.ifNull();
  final hasUpdate = extension.hasUpdate.ifNull();

  final configurableSources =
      ref.read(sourceListProvider).value?.where((s) {
        return s.$extension.pkgName == extension.pkgName && s.isConfigurable;
      }).toList() ??
      const [];

  await showMenu<void>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      PopupMenuItem(
        onTap: () => openExtensionInfo(context, pkgName: extension.pkgName),
        child: ChapterMenuRow(
          icon: FluentIcons.info_24_regular,
          label: context.l10n.extensionInfo,
        ),
      ),
      if (configurableSources.length == 1)
        PopupMenuItem(
          onTap: () => SourcePreferenceRoute(
            sourceId: configurableSources.single.id,
          ).push(context),
          child: ChapterMenuRow(
            icon: FluentIcons.settings_24_regular,
            label: context.l10n.settings,
          ),
        ),
      const PopupMenuDivider(),
      if (hasUpdate)
        PopupMenuItem(
          enabled: canInstall,
          onTap: () => guard((actions) => actions.update(extension.pkgName)),
          child: ChapterMenuRow(
            icon: FluentIcons.arrow_clockwise_24_regular,
            label: context.l10n.update,
          ),
        ),
      if (installed) ...[
        PopupMenuItem(
          enabled: canInstall && canUninstall,
          onTap: () => guard(
            (actions) => actions.reinstall(
              extension.pkgName,
              languageCode: extension.language?.code,
            ),
          ),
          child: ChapterMenuRow(
            icon: FluentIcons.arrow_clockwise_24_regular,
            label: context.l10n.reinstall,
          ),
        ),
        PopupMenuItem(
          enabled: canUninstall,
          onTap: uninstall,
          child: _RedMenuRow(
            icon: FluentIcons.delete_24_regular,
            label: '${context.l10n.uninstall}...',
          ),
        ),
      ] else
        PopupMenuItem(
          enabled: canInstall,
          onTap: () => guard(
            (actions) => actions.install(
              extension.pkgName,
              languageCode: extension.language?.code,
            ),
          ),
          child: ChapterMenuRow(
            icon: FluentIcons.arrow_circle_down_24_regular,
            label: context.l10n.install,
          ),
        ),
    ],
    popUpAnimationStyle: context.motionStyle,
  );
}

class _RedMenuRow extends StatelessWidget {
  const _RedMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final error = context.theme.colorScheme.error;
    return Row(
      children: [
        Icon(icon, size: 20, color: error),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: error)),
        ),
      ],
    );
  }
}
