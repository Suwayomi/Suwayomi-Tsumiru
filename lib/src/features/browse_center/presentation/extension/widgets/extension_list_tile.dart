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
    final isLoading = useState(false);
    return ListTile(
      key: key,
      leading: ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImageWithCpi(
          url: extension.iconUrl,
          outerSize: const Size.square(48),
          innerSize: const Size.square(24),
          isLoading: isLoading.value,
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
        isLoading: isLoading,
        ref: ref,
      ),
    );
  }
}

class ExtensionListTileTailing extends StatelessWidget {
  const ExtensionListTileTailing({
    super.key,
    required this.extension,
    required this.isLoading,
    required this.ref,
  });

  final Extension extension;
  final ValueNotifier<bool> isLoading;
  final WidgetRef ref;

  /// Runs an extension action with the button's spinner and error toast.
  /// [ExtensionActions] refreshes both the extension and the source list, so no
  /// caller needs to pass a refresh callback down.
  Future<void> _run(
    Future<void> Function(ExtensionActions actions) action,
  ) async {
    try {
      isLoading.value = true;
      await AppUtils.guard(
        () => action(ref.read(extensionActionsProvider)),
        ref.read(toastProvider),
      );
      isLoading.value = false;
    } catch (_) {
      // The refresh this action triggers can rebuild the list and dispose the
      // tile out from under the spinner.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (extension.isObsolete.ifNull()) {
      return OutlinedButton(
        onPressed: extension.isInstalled.ifNull() && !isLoading.value
            ? () => _run((actions) => actions.uninstall(extension.pkgName))
            : null,
        child: Text(
          context.l10n.obsolete,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    } else {
      if (extension.isInstalled.ifNull()) {
        final actionButton = TextButton(
          onPressed: (!isLoading.value)
              ? () => _run((actions) async {
                    if (extension.pkgName.isBlank) {
                      throw context.l10n.errorExtension;
                    }
                    if (extension.hasUpdate.ifNull()) {
                      await actions.update(extension.pkgName);
                    } else {
                      await actions.uninstall(extension.pkgName);
                    }
                  })
              : null,
          child: Text(
            extension.hasUpdate.ifNull()
                ? isLoading.value
                    ? context.l10n.updating
                    : context.l10n.update
                : isLoading.value
                    ? context.l10n.uninstalling
                    : context.l10n.uninstall,
          ),
        );
        // When an update is pending the single button reads "Update", which used
        // to leave no way to uninstall the extension. Keep Update but add a
        // separate uninstall affordance so a pending update can't trap it (#290).
        if (!extension.hasUpdate.ifNull()) return actionButton;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            actionButton,
            IconButton(
              tooltip: context.l10n.uninstall,
              icon: const Icon(Icons.delete_outline),
              onPressed: isLoading.value
                  ? null
                  : () => _run((actions) => actions.uninstall(
                        extension.pkgName,
                      )),
            ),
          ],
        );
      } else {
        return TextButton(
          onPressed: !isLoading.value
              ? () => _run((actions) async {
                    if (extension.pkgName.isBlank) {
                      throw context.l10n.errorExtension;
                    }
                    await actions.install(
                      extension.pkgName,
                      languageCode: extension.language?.code,
                    );
                  })
              : null,
          child: Text(
            isLoading.value ? context.l10n.installing : context.l10n.install,
          ),
        );
      }
    }
  }
}
