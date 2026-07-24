// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../settings/presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../../../data/recommendations/recommendation_repository.dart';
import '../../recommends/recommendation_card.dart';

/// Komikku's inline "Suggestions" row on the manga details page: a header with a
/// forward arrow that opens the grouped recommendations screen, above a
/// horizontal row of cover cards. Komikku sources this from the source's related
/// mangas; Suwayomi has no such query, so it reuses the tracker engine.
class RecommendsRow extends ConsumerWidget {
  const RecommendsRow({super.key, required this.mangaId, this.mangaTitle});

  final int mangaId;
  final String? mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showRecommendationsProvider).ifNull(true) ||
        ref.watch(recommendsInOverflowProvider).ifNull(false)) {
      return const SizedBox.shrink();
    }
    final recs = ref.watch(mangaRecommendationsProvider(mangaId));
    // Drop the whole section when it resolves to nothing, matching Komikku only
    // showing the row when the related list is non-empty.
    if (recs.hasValue && recs.value!.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 0),
        InkWell(
          onTap: () =>
              RecommendsRoute(mangaId: mangaId, mangaTitle: mangaTitle)
                  .push(context),
          child: Padding(
            padding: KEdgeInsets.h16v8.size,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.suggestions,
                    style: context.textTheme.titleMedium),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: recs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, i) => RecommendationCard(rec: list[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 0),
      ],
    );
  }
}
