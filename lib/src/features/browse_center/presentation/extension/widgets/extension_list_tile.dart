// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/server_image.dart';
import '../../../domain/content_rating.dart';
import '../../../domain/extension/extension_model.dart';
import '../controller/extension_actions.dart';

class ExtensionListTile extends HookConsumerWidget {
  const ExtensionListTile({
    super.key,
    required this.extension,
  });

  final Extension extension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runningAction = useState<String?>(null);
    return ListTile(
      key: key,
      leading: ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImageWithCpi(
          url: extension.iconUrl,
          outerSize: const Size.square(48),
          innerSize: const Size.square(24),
          isLoading: runningAction.value != null,
        ),
      ),
      title: Text(
        extension.name,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text.rich(
        TextSpan(
          text: "${extension.language?.displayName} ",
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: [
            if (extension.versionName.isNotBlank)
              TextSpan(
                text: "${extension.versionName} ",
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
            if (isNsfwFromWarning(extension.contentWarning))
              TextSpan(
                text: context.l10n.nsfw18,
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: Colors.redAccent,
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

  /// The label of the action in flight, or null when the tile is idle.
  final ValueNotifier<String?> runningAction;
  final WidgetRef ref;

  /// Runs an extension action with the button's spinner and error toast.
  /// [ExtensionActions] refreshes both the extension and the source list, so no
  /// caller needs to pass a refresh callback down.
  Future<void> _run(
    String label,
    Future<void> Function(ExtensionActions actions) action,
  ) async {
    try {
      runningAction.value = label;
      await AppUtils.guard(
        () => action(ref.read(extensionActionsProvider)),
        ref.read(toastProvider),
      );
      runningAction.value = null;
    } catch (_) {
      // The refresh this action triggers can rebuild the list and dispose the
      // tile out from under the spinner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = runningAction.value;
    if (extension.isObsolete.ifNull()) {
      return OutlinedButton(
        onPressed: extension.isInstalled.ifNull() && running == null
            ? () => _run(
                  context.l10n.uninstalling,
                  (actions) => actions.uninstall(extension.pkgName),
                )
            : null,
        child: Text(
          context.l10n.obsolete,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    if (!extension.isInstalled.ifNull()) {
      return TextButton(
        onPressed: running == null
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
    }
    final hasUpdate = extension.hasUpdate.ifNull();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: running == null
              ? () => _run(
                    hasUpdate
                        ? context.l10n.updating
                        : context.l10n.uninstalling,
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
            running ??
                (hasUpdate ? context.l10n.update : context.l10n.uninstall),
          ),
        ),
        // A third control squeezes the extension name off a phone screen.
        if (hasUpdate)
          PopupMenuButton<VoidCallback>(
            enabled: running == null,
            onSelected: (selected) => selected(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _reinstall(context),
                child: Text(context.l10n.reinstall),
              ),
              PopupMenuItem(
                value: () => _run(
                  context.l10n.uninstalling,
                  (actions) => actions.uninstall(extension.pkgName),
                ),
                child: Text(context.l10n.uninstall),
              ),
            ],
          )
        else
          IconButton(
            tooltip: context.l10n.reinstall,
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: running == null ? _reinstall(context) : null,
          ),
      ],
    );
  }

  /// Repairs an extension with no loaded sources or a phantom update (#428).
  VoidCallback _reinstall(BuildContext context) => () => _run(
        context.l10n.reinstalling,
        (actions) => actions.reinstall(
          extension.pkgName,
          languageCode: extension.language?.code,
        ),
      );
}
