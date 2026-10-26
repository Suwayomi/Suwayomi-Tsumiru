// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../../domain/content_rating.dart';
import '../../../domain/extension/extension_model.dart';
import '../controller/extension_actions.dart';
import 'extension_context_menu.dart';
import 'extension_info_dialog.dart';

class ExtensionListTile extends HookConsumerWidget {
  const ExtensionListTile({super.key, required this.extension});

  final Extension extension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runningAction = useState<String?>(null);
    final access = ref.watch(settledAccountAccessProvider);
    return ListTile(
      key: key,
      onTap: () => openExtensionInfo(context, pkgName: extension.pkgName),
      leading: ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImageWithCpi(
          url: extension.iconUrl,
          outerSize: const Size.square(48),
          innerSize: const Size.square(24),
          isLoading: runningAction.value != null,
        ),
      ),
      title: Text(extension.name, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(
          text: "${extension.language?.displayName} ",
          style: const TextStyle(fontWeight: FontWeight.w600),
          children: [
            if (!access.allows(
              extension.isInstalled.ifNull()
                  ? Enum$UserPermission.UNINSTALL_EXTENSIONS
                  : Enum$UserPermission.INSTALL_EXTENSIONS,
            ))
              TextSpan(
                text: '${context.l10n.accountPermissionDenied} ',
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
            if (extension.versionName.isNotBlank)
              TextSpan(
                text: "${extension.versionName} ",
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
            if (isNsfwFromWarning(extension.contentWarning))
              TextSpan(
                text: context.l10n.nsfw18,
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: context.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
      trailing: ExtensionListTileTailing(
        extension: extension,
        runningAction: runningAction,
        ref: ref,
      ),
    );
  }
}

class ExtensionListTileTailing extends StatelessWidget {
  const ExtensionListTileTailing({
    super.key,
    required this.extension,
    required this.runningAction,
    required this.ref,
  });

  final Extension extension;

  final ValueNotifier<String?> runningAction;
  final WidgetRef ref;

  Future<void> _run(
    String label,
    Future<void> Function(ExtensionActions actions) action,
  ) async {
    try {
      if (label == ref.context.l10n.uninstalling) {
        final context = ref.context;
        if (!await confirmAction(
              context,
              title: context.l10n.uninstall,
              message: context.l10n.confirmUninstallMessage,
              action: context.l10n.uninstall,
            ) ||
            !context.mounted) {
          return;
        }
      }
      runningAction.value = label;
      await AppUtils.guard(
        () => action(ref.read(extensionActionsProvider)),
        ref.read(toastProvider),
      );
      runningAction.value = null;
    } catch (_) {
      // Refreshing can dispose this tile before the action completes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(settledAccountAccessProvider);
    final canInstall = access.allows(Enum$UserPermission.INSTALL_EXTENSIONS);
    final canUninstall = access.allows(
      Enum$UserPermission.UNINSTALL_EXTENSIONS,
    );
    final running = runningAction.value;
    final desktop = context.usesDesktopShell;
    if (extension.isObsolete.ifNull()) {
      final button = OutlinedButton(
        onPressed:
            extension.isInstalled.ifNull() && canUninstall && running == null
            ? () => _run(
                context.l10n.uninstalling,
                (actions) => actions.uninstall(extension.pkgName),
              )
            : null,
        child: Text(
          context.l10n.obsolete,
          style: TextStyle(color: context.colorScheme.error),
        ),
      );
      if (!desktop) return button;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          _DesktopMoreButton(extension: extension, ref: ref),
        ],
      );
    }
    if (!extension.isInstalled.ifNull()) {
      final installButton = TextButton(
        onPressed: canInstall && running == null
            ? () => _run(context.l10n.installing, (actions) async {
                if (extension.pkgName.isBlank) {
                  throw context.l10n.errorExtension;
                }
                await actions.install(
                  extension.pkgName,
                  languageCode: extension.language?.code,
                );
              })
            : null,
        child: Text(running ?? context.l10n.install),
      );
      if (!desktop) return installButton;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          installButton,
          _DesktopMoreButton(extension: extension, ref: ref),
        ],
      );
    }
    final hasUpdate = extension.hasUpdate.ifNull();
    final actionButton = TextButton(
      onPressed: (hasUpdate || canUninstall) && running == null
          ? () => _run(
              hasUpdate ? context.l10n.updating : context.l10n.uninstalling,
              (actions) async {
                if (extension.pkgName.isBlank) {
                  throw context.l10n.errorExtension;
                }
                if (hasUpdate) {
                  await actions.update(extension.pkgName);
                } else {
                  await actions.uninstall(extension.pkgName);
                }
              },
            )
          : null,
      child: Text(
        running ?? (hasUpdate ? context.l10n.update : context.l10n.uninstall),
      ),
    );
    if (desktop) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          actionButton,
          _DesktopMoreButton(extension: extension, ref: ref),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton,
        // A third control squeezes the extension name off a phone screen.
        if (hasUpdate)
          PopupMenuButton<VoidCallback>(
            icon: const Icon(
              FluentIcons.more_vertical_24_regular,
            ),
            enabled: canUninstall && running == null,
            onSelected: (selected) => selected(),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: canInstall && canUninstall,
                value: _reinstall(context),
                child: ChapterMenuRow(
                  icon: FluentIcons.arrow_clockwise_24_regular,
                  label: context.l10n.reinstall,
                ),
              ),
              PopupMenuItem(
                value: () => _run(
                  context.l10n.uninstalling,
                  (actions) => actions.uninstall(extension.pkgName),
                ),
                child: ChapterMenuRow(
                  icon: FluentIcons.delete_24_regular,
                  label: context.l10n.uninstall,
                ),
              ),
            ],
            popUpAnimationStyle: context.motionStyle,
          )
        else
          IconButton(
            tooltip: canInstall && canUninstall
                ? context.l10n.reinstall
                : context.l10n.accountPermissionDenied,
            icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
            onPressed: canInstall && canUninstall && running == null
                ? _reinstall(context)
                : null,
          ),
      ],
    );
  }

  VoidCallback _reinstall(BuildContext context) =>
      () => _run(
        context.l10n.reinstalling,
        (actions) => actions.reinstall(
          extension.pkgName,
          languageCode: extension.language?.code,
        ),
      );
}

class _DesktopMoreButton extends StatelessWidget {
  const _DesktopMoreButton({required this.extension, required this.ref});

  final Extension extension;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.more,
      icon: const Icon(FluentIcons.more_vertical_24_regular),
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        showExtensionContextMenu(
          context: context,
          ref: ref,
          position: menuAnchorForRect(
            context,
            box.localToGlobal(Offset.zero) & box.size,
          ),
          extension: extension,
        );
      },
    );
  }
}
