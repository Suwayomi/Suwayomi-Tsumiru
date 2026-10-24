// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../controller/manga_details_controller.dart';

class MangaRatingBar extends HookConsumerWidget {
  const MangaRatingBar({
    super.key,
    required this.mangaId,
    this.compact = false,
  });

  final int mangaId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(mangaRatingProvider(mangaId: mangaId));
    final hovered = useState<int?>(null);
    final pending = useState<int?>(null);
    final row = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (!compact) ...[
          Text(context.l10n.yourRating, style: context.textTheme.titleSmall),
          const Spacer(),
        ],
        for (int star = 1; star <= 5; star++)
          HookBuilder(
            builder: (context) {
              final pop = useAnimationController(
                duration: const Duration(milliseconds: 180),
              );
              final value = useAnimation(pop);
              final scale = context.reduceMotion
                  ? 1.0
                  : pop.isAnimating
                  ? 1 + .35 * (value < .4 ? value / .4 : (1 - value) / .6)
                  : hovered.value == star
                  ? 1.18
                  : 1.0;
              final filled = star <= (hovered.value ?? pending.value ?? rating);
              return MouseRegion(
                onEnter: (_) => hovered.value = star,
                onExit: (_) => hovered.value = null,
                child: InkResponse(
                  radius: 20,
                  onTap: () async {
                    if (!context.reduceMotion) pop.forward(from: 0);
                    final next = (pending.value ?? rating) == star ? 0 : star;
                    pending.value = next;
                    await ref
                        .read(mangaRatingProvider(mangaId: mangaId).notifier)
                        .update(next);
                    if (context.mounted && pending.value == next) {
                      pending.value = null;
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Transform.scale(
                      scale: scale,
                      child: Icon(
                        filled ? FluentIcons.star_24_filled : FluentIcons.star_24_regular,
                        size: 24,
                        color: filled
                            ? brandStarColor(context.theme.brightness)
                            : context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
    return Tooltip(
      message: context.l10n.yourRating,
      child: compact
          ? row
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: row,
            ),
    );
  }
}
