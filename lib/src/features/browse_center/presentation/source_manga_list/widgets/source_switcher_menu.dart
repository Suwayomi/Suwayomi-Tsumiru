// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show menuAnchorForRect;
import '../../../domain/source/source_model.dart';
import '../../source/controller/source_controller.dart';

Future<void> showSourceSwitcherMenu({
  required BuildContext context,
  required WidgetRef ref,
  required GlobalKey buttonKey,
  required String currentSourceId,
}) async {
  final box = buttonKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  final position = menuAnchorForRect(
    context,
    box.localToGlobal(Offset.zero) & box.size,
  );
  final sources = ref.read(browsableSourceListProvider).value ?? const [];
  final pinned = pinnedSourcesFrom(sources);
  final recentIds = ref.read(sourceRecentIdsProvider) ?? const <String>[];
  final byId = {for (final source in sources) source.id: source};
  final recent = [
    for (final id in recentIds)
      if (id != currentSourceId && byId.containsKey(id)) byId[id]!,
  ];
  Widget heading(String text) => Text(
    text.toUpperCase(),
    style: context.theme.textTheme.labelSmall?.copyWith(
      color: context.theme.colorScheme.onSurfaceVariant,
    ),
  );
  PopupMenuItem<String> sourceItem(SourceDto source) => PopupMenuItem<String>(
    value: source.id,
    child: Row(
      children: [
        ClipRRect(
          borderRadius: KBorderRadius.r8.radius,
          child: ServerImage(
            imageUrl: source.iconUrl,
            size: const Size.square(24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            source.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (source.id == currentSourceId)
          Icon(
            FluentIcons.checkmark_24_regular,
            size: 18,
            color: context.theme.colorScheme.primary,
          ),
      ],
    ),
  );
  final choice = await showMenu<String>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      if (pinned.isNotEmpty) ...[
        PopupMenuItem<String>(
          enabled: false,
          child: heading(context.l10n.pinned),
        ),
        for (final source in pinned) sourceItem(source),
      ],
      if (recent.isNotEmpty) ...[
        PopupMenuItem<String>(
          enabled: false,
          child: heading(context.l10n.recent),
        ),
        for (final source in recent) sourceItem(source),
      ],
      if (pinned.isNotEmpty || recent.isNotEmpty) const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: ':all',
        child: Row(
          children: [
            Icon(
              FluentIcons.globe_24_regular,
              size: 20,
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(context.l10n.browseAllSources)),
          ],
        ),
      ),
    ],
    popUpAnimationStyle: context.motionStyle,
  );
  if (choice == null || !context.mounted) return;
  if (choice == ':all') {
    const BrowseSourceRoute().go(context);
    return;
  }
  ref.read(sourceLastUsedProvider.notifier).update(choice);
  if (choice == currentSourceId || !context.mounted) return;
  SourceTypeRoute(sourceId: choice, sourceType: SourceType.POPULAR).go(context);
}
