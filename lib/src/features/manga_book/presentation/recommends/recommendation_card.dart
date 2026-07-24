// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../data/recommendations/recommendation_provider.dart';

/// A single recommendation cover card. Recommendations are external titles, not
/// local library entries, so tapping searches globally by title.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.rec});

  final Recommendation rec;

  @override
  Widget build(BuildContext context) {
    // Komikku's MangaItem: 96dp-wide comfortable-grid card (2:3 cover -> 144
    // tall) with the title below.
    return SizedBox(
      width: 96,
      child: InkWell(
        borderRadius: KBorderRadius.r8.radius,
        onTap: () => GlobalSearchRoute(query: rec.title).push(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: KBorderRadius.r8.radius,
              child: SizedBox(
                width: 96,
                height: 144,
                child: rec.coverUrl != null
                    ? Image.network(
                        rec.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Colors.black26),
                      )
                    : const ColoredBox(color: Colors.black26),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rec.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
