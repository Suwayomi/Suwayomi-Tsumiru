// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/endpoints.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show ChapterMenuRow;
import '../../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';
import '../../extension/widgets/extension_info_dialog.dart';
import '../controller/source_controller.dart';

Future<void> hideSource(
  WidgetRef ref,
  BuildContext context,
  SourceDto source,
) async {
  // Undo must survive the card disposing, so refresh runs off the container.
  final container = ProviderScope.containerOf(context, listen: false);
  final toast = ref.read(toastProvider);
  final hiddenMessage = context.l10n.sourceHidden(source.displayName);
  final undoLabel = context.l10n.undo;
  try {
    await container
        .read(sourceRepositoryProvider)
        .setSourceHidden(source.id, true);
    container.invalidate(sourceListProvider);
  } catch (e) {
    if (context.mounted) toast?.showError(e.toString());
    return;
  }
  if (!context.mounted) return;
  toast?.showWithAction(
    hiddenMessage,
    actionLabel: undoLabel,
    onAction: () {
      unawaited(
        container
            .read(sourceRepositoryProvider)
            .setSourceHidden(source.id, false)
            .then((_) => container.invalidate(sourceListProvider)),
      );
    },
  );
}

/// Pin toggle runs off the container so it survives the card disposing mid-mutation.
Future<void> toggleSourcePin(BuildContext context, SourceDto source) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container
        .read(sourceRepositoryProvider)
        .setSourcePinned(source.id, !source.isPinned);
    container.invalidate(sourceListProvider);
  } catch (e) {
    if (context.mounted) {
      container.read(toastProvider)?.showError(e.toString());
    }
  }
}

void openSourceHomepage(BuildContext context, WidgetRef ref, String? homeUrl) {
  if (homeUrl.isBlank) return;
  final api = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
  );
  launchUrlInWeb(
    context,
    '${api.endsWith('/') ? api : '$api/'}webview#$homeUrl',
    ref.read(toastProvider),
  );
}

Future<void> showSourceContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required SourceDto source,
}) async {
  Future<void> openPopular() async {
    ref.read(sourceLastUsedProvider.notifier).update(source.id);
    return SourceTypeRoute(
      sourceId: source.id,
      sourceType: SourceType.POPULAR,
    ).push(context);
  }

  final pinned = source.isPinned;
  await showMenu<void>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      PopupMenuItem(
        onTap: openPopular,
        child: ChapterMenuRow(
          icon: FluentIcons.star_24_regular,
          label: context.l10n.sourceTypePopular,
        ),
      ),
      if (source.supportsLatest)
        PopupMenuItem(
          onTap: () {
            ref.read(sourceLastUsedProvider.notifier).update(source.id);
            SourceTypeRoute(
              sourceId: source.id,
              sourceType: SourceType.LATEST,
            ).push(context);
          },
          child: ChapterMenuRow(
            icon: FluentIcons.clock_24_regular,
            label: context.l10n.sourceTypeLatest,
          ),
        ),
      PopupMenuItem(
        onTap: () => SourceTypeRoute(
          sourceId: source.id,
          sourceType: SourceType.SEARCH,
        ).push(context),
        child: ChapterMenuRow(
          icon: FluentIcons.search_24_regular,
          label: context.l10n.search,
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: () => toggleSourcePin(context, source),
        child: ChapterMenuRow(
          icon: pinned ? FluentIcons.pin_24_filled : FluentIcons.pin_24_regular,
          label: pinned ? context.l10n.unpinSource : context.l10n.pinSource,
        ),
      ),
      if (source.isConfigurable)
        PopupMenuItem(
          onTap: () => SourcePreferenceRoute(sourceId: source.id).push(context),
          child: ChapterMenuRow(
            icon: FluentIcons.settings_24_regular,
            label: context.l10n.settings,
          ),
        ),
      if (source.homeUrl.isNotBlank)
        PopupMenuItem(
          onTap: () => openSourceHomepage(context, ref, source.homeUrl),
          child: ChapterMenuRow(
            icon: FluentIcons.globe_24_regular,
            label: context.l10n.openHomepage,
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: () =>
            openExtensionInfo(context, pkgName: source.$extension.pkgName),
        child: ChapterMenuRow(
          icon: FluentIcons.info_24_regular,
          label: context.l10n.extensionInfo,
        ),
      ),
      PopupMenuItem(
        onTap: () => hideSource(ref, context, source),
        child: ChapterMenuRow(
          icon: FluentIcons.eye_off_24_regular,
          label: context.l10n.hideSource,
        ),
      ),
    ],
    popUpAnimationStyle: context.motionStyle,
  );
}
