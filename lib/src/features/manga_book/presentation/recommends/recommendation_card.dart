// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/navigation.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../data/recommendations/recommendation_provider.dart';
import '../../domain/manga/manga_model.dart';

@visibleForTesting
MangaDto? matchLibraryRecommendation(String title, List<MangaDto>? library) {
  final want = title.trim().toLowerCase();
  if (want.isEmpty) return null;
  for (final entry in library ?? const <MangaDto>[]) {
    if (entry.title.trim().toLowerCase() == want) return entry;
  }
  return null;
}

/// A single recommendation cover card. Tapping opens the series page when the
/// recommended title already matches a library entry, else searches globally.
class RecommendationCard extends HookConsumerWidget {
  const RecommendationCard({super.key, required this.rec, this.width = 96});

  final Recommendation rec;
  final double width;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    MangaDto? match;
    try {
      match = matchLibraryRecommendation(
        rec.title,
        await ref.read(libraryMangaListProvider.future),
      );
    } catch (_) {
      match = null;
    }
    if (!context.mounted) return;
    if (match != null) {
      MangaRoute(mangaId: match.id).push(context);
    } else {
      openGlobalSearch(context, query: rec.title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final cs = context.colorScheme;
    return SizedBox(
      width: width,
      child: InkWell(
        onHover: (value) => hovered.value = value,
        borderRadius: KBorderRadius.r8.radius,
        onTap: () => _open(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: KBorderRadius.r8.radius,
              child: SizedBox(
                width: width,
                height: width * 1.5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (rec.coverUrl != null)
                      Image.network(
                        rec.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                      )
                    else
                      ColoredBox(color: cs.surfaceContainerHighest),
                    if (context.isDesktop && hovered.value)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: KBorderRadius.r8.radius,
                          border: Border.all(
                            color: cs.primary.withValues(alpha: .75),
                            width: 2,
                          ),
                        ),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onHover: (value) => hovered.value = value,
                        onTap: () => _open(context, ref),
                        borderRadius: KBorderRadius.r8.radius,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rec.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.isDesktop && hovered.value ? cs.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
