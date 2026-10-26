// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show menuAnchorForPoint, menuAnchorForRect;
import '../../../domain/source/source_model.dart';
import '../controller/source_controller.dart';
import 'source_context_menu.dart';

class SourceCard extends HookConsumerWidget {
  const SourceCard({super.key, required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final menuOpen = useState(false);
    final moreKey = useMemoized(GlobalKey.new);

    void openPopular() {
      ref.read(sourceLastUsedProvider.notifier).update(source.id);
      SourceTypeRoute(
        sourceId: source.id,
        sourceType: SourceType.POPULAR,
      ).go(context);
    }

    Future<void> openMenu(RelativeRect position) async {
      menuOpen.value = true;
      try {
        await showSourceContextMenu(
          context: context,
          ref: ref,
          position: position,
          source: source,
        );
      } finally {
        menuOpen.value = false;
      }
    }

    void openMenuAt(Offset point) =>
        openMenu(menuAnchorForPoint(context, point));

    void openButtonMenu() {
      final box = moreKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      openMenu(
        menuAnchorForRect(context, box.localToGlobal(Offset.zero) & box.size),
      );
    }

    final popularLocation = SourceTypeRoute(
      sourceId: source.id,
      sourceType: SourceType.POPULAR,
    ).location;
    final leadingBlock = Row(
      children: [
        ClipRRect(
          borderRadius: KBorderRadius.r8.radius,
          child: ServerImage(
            imageUrl: source.iconUrl,
            size: const Size.square(48),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.name,
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
      ],
    );
    void openLatest() {
      ref.read(sourceLastUsedProvider.notifier).update(source.id);
      SourceTypeRoute(
        sourceId: source.id,
        sourceType: SourceType.LATEST,
      ).go(context);
    }

    final trailingActions = [
      if (source.supportsLatest.ifNull())
        TextButton(onPressed: openLatest, child: Text(context.l10n.latest)),
      _CardPinButton(source: source),
      if (hovered.value || menuOpen.value)
        IconButton(
          key: moreKey,
          tooltip: context.l10n.more,
          icon: const Icon(FluentIcons.more_vertical_24_regular),
          onPressed: openButtonMenu,
        ),
    ];
    // The Latest button cannot sit inside the row link: the anchor would cover it.
    final webRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: WebRouteLink(
              location: popularLocation,
              builder: (context, openInNewTab) => InkWell(
                onTap: () => WebRouteLink.handleTap(openInNewTab, openPopular),
                child: leadingBlock,
              ),
            ),
          ),
          ...trailingActions,
        ],
      ),
    );
    final nativeRow = WebRouteLink(
      location: popularLocation,
      builder: (context, openInNewTab) => InkWell(
        onTap: () => WebRouteLink.handleTap(openInNewTab, openPopular),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: leadingBlock),
              ...trailingActions,
            ],
          ),
        ),
      ),
    );
    return GestureDetector(
      onSecondaryTapDown: (details) => openMenuAt(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: kIsWeb ? webRow : nativeRow,
        ),
      ),
    );
  }
}

class _CardPinButton extends ConsumerWidget {
  const _CardPinButton({required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = source.isPinned;
    return IconButton(
      tooltip: pinned ? context.l10n.unpinSource : context.l10n.pinSource,
      icon: Icon(
        pinned ? FluentIcons.pin_24_filled : FluentIcons.pin_24_regular,
      ),
      color: pinned ? context.theme.colorScheme.primary : null,
      onPressed: () => toggleSourcePin(context, source),
    );
  }
}
