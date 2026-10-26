// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../account/data/account_providers.dart';
import '../../../domain/content_rating.dart';
import '../../../domain/extension/extension_model.dart';
import '../../../domain/source/source_model.dart';
import '../../source/controller/source_controller.dart';
import '../controller/extension_actions.dart';
import '../controller/extension_controller.dart';

Future<void> openExtensionInfo(
  BuildContext context, {
  required String pkgName,
}) {
  if (!context.usesDesktopShell) {
    return ExtensionInfoRoute(pkgName: pkgName).push(context);
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(pkgName: pkgName),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _DialogBody(pkgName: pkgName),
              ),
            ),
          ],
        ),
      ),
    ),
    animationStyle: context.motionStyle,
  );
}

class _DialogHeader extends ConsumerWidget {
  const _DialogHeader({required this.pkgName});

  final String pkgName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extension = ref
        .watch(extensionProvider)
        .value
        ?.where((e) => e.pkgName == pkgName)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          if (extension != null)
            ClipRRect(
              borderRadius: KBorderRadius.r12.radius,
              child: ServerImageWithCpi(
                url: extension.iconUrl,
                outerSize: const Size.square(64),
                innerSize: const Size.square(32),
                isLoading: false,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        extension?.name ?? pkgName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.textTheme.titleLarge,
                      ),
                    ),
                    if (extension != null &&
                        isNsfwFromWarning(extension.contentWarning))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          context.l10n.nsfw18,
                          style: context.theme.textTheme.titleSmall?.copyWith(
                            color: context.theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                if (extension != null)
                  Text(
                    extension.pkgName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.bodySmall?.copyWith(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _DialogBody extends HookConsumerWidget {
  const _DialogBody({required this.pkgName});

  final String pkgName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionProvider);
    final sources = ref.watch(sourceListProvider);
    final running = useState<String?>(null);
    return extensions.showUiWhenData(context, (data) {
      final extension = data?.where((e) => e.pkgName == pkgName).firstOrNull;
      if (extension == null) return const SizedBox.shrink();
      final store = extension.extensionStore?.name ?? extension.storeIndexUrl;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 8,
            children: [
              _InfoTile(
                label: context.l10n.extensionVersion,
                value: extension.versionName,
              ),
              _InfoTile(
                label: context.l10n.extensionLanguage,
                value: extension.language?.displayName ?? extension.lang,
              ),
              _InfoTile(
                label: context.l10n.extensionStore,
                value: store.isNotBlank ? store! : '–',
              ),
              _InfoTile(
                label: context.l10n.extensionLibrary,
                value: extension.extensionLib.isNotBlank
                    ? extension.extensionLib!
                    : '–',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DialogActions(
            extension: extension,
            runningAction: running,
            ref: ref,
          ),
          const Divider(height: 24),
          Text(
            context.l10n.sources,
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          sources.showUiWhenData(
            context,
            (items) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final source in items ?? [])
                  if (source.$extension.pkgName == pkgName)
                    _SourceRow(source: source),
              ],
            ),
            refresh: () => ref.invalidate(sourceListProvider),
          ),
        ],
      );
    }, refresh: () => ref.invalidate(extensionProvider));
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: KBorderRadius.r12.radius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.extension,
    required this.runningAction,
    required this.ref,
  });

  final Extension extension;
  final ValueNotifier<String?> runningAction;
  final WidgetRef ref;

  Future<void> _run(
    String label,
    Future<void> Function(ExtensionActions actions) action, {
    bool confirm = false,
  }) async {
    if (confirm) {
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
    try {
      runningAction.value = null;
    } catch (_) {
      // Refreshing can dispose this dialog before the action completes.
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
    final busy = running != null;
    final installed = extension.isInstalled.ifNull();
    final hasUpdate = extension.hasUpdate.ifNull();
    final languageCode = extension.language?.code;
    final buttons = <Widget>[];
    if (extension.isObsolete.ifNull()) {
      buttons.add(
        OutlinedButton(
          onPressed: installed && canUninstall && !busy
              ? () => _run(
                  context.l10n.uninstalling,
                  (actions) => actions.uninstall(extension.pkgName),
                  confirm: true,
                )
              : null,
          child: Text(
            running ?? context.l10n.obsolete,
            style: TextStyle(color: context.colorScheme.error),
          ),
        ),
      );
    } else if (!installed) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: canInstall && !busy
              ? () => _run(context.l10n.installing, (actions) async {
                  if (extension.pkgName.isBlank) {
                    throw context.l10n.errorExtension;
                  }
                  await actions.install(
                    extension.pkgName,
                    languageCode: languageCode,
                  );
                })
              : null,
          icon: const Icon(FluentIcons.arrow_circle_down_24_regular, size: 20),
          label: Text(running ?? context.l10n.install),
        ),
      );
    } else {
      if (hasUpdate) {
        buttons.add(
          OutlinedButton.icon(
            onPressed: canInstall && !busy
                ? () => _run(context.l10n.updating, (actions) async {
                    if (extension.pkgName.isBlank) {
                      throw context.l10n.errorExtension;
                    }
                    await actions.update(extension.pkgName);
                  })
                : null,
            icon: const Icon(FluentIcons.arrow_clockwise_24_regular, size: 20),
            label: Text(running ?? context.l10n.update),
          ),
        );
      }
      buttons.add(
        OutlinedButton.icon(
          onPressed: canInstall && canUninstall && !busy
              ? () => _run(context.l10n.reinstalling, (actions) async {
                  if (extension.pkgName.isBlank) {
                    throw context.l10n.errorExtension;
                  }
                  await actions.reinstall(
                    extension.pkgName,
                    languageCode: languageCode,
                  );
                })
              : null,
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular, size: 20),
          label: Text(running ?? context.l10n.reinstall),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: canUninstall && !busy
              ? () => _run(
                  context.l10n.uninstalling,
                  (actions) => actions.uninstall(extension.pkgName),
                  confirm: true,
                )
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colorScheme.error,
          ),
          icon: const Icon(FluentIcons.delete_24_regular, size: 20),
          label: Text(running ?? context.l10n.uninstall),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.source});

  final SourceDto source;

  // Dialog sits on the root navigator above the destination, so pop first.
  void _open(BuildContext context, GoRouteData route) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(route.location);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: KBorderRadius.r12.radius,
      onTap: () => _open(
        context,
        SourceTypeRoute(sourceId: source.id, sourceType: SourceType.POPULAR),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: KBorderRadius.r8.radius,
              child: ServerImageWithCpi(
                isLoading: false,
                url: source.iconUrl,
                outerSize: const Size.square(40),
                innerSize: const Size.square(20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.titleSmall,
                  ),
                  if (source.language?.displayName.isNotBlank ?? false)
                    Text(
                      source.language?.displayName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.bodySmall?.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (source.supportsLatest)
              TextButton(
                onPressed: () => _open(
                  context,
                  SourceTypeRoute(
                    sourceId: source.id,
                    sourceType: SourceType.LATEST,
                  ),
                ),
                child: Text(context.l10n.latest),
              ),
            if (source.isConfigurable)
              IconButton(
                tooltip: context.l10n.settings,
                icon: const Icon(FluentIcons.settings_24_regular),
                onPressed: () =>
                    _open(context, SourcePreferenceRoute(sourceId: source.id)),
              ),
          ],
        ),
      ),
    );
  }
}
