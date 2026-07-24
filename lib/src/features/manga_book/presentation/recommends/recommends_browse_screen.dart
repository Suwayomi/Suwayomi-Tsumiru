// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/emoticons.dart';
import '../../data/recommendations/recommendation_repository.dart';

/// Komikku's BrowseRecommendsScreen: one provider's full recommendation list as
/// a cover grid, opened from a section header on the recommendations screen.
class RecommendsBrowseScreen extends ConsumerWidget {
  const RecommendsBrowseScreen({
    super.key,
    required this.mangaId,
    required this.providerName,
  });

  final int mangaId;

  /// The provider [key] (name+category), not the display name — MangaUpdates
  /// ships two providers under one name, so the lookup must be by key.
  final String providerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs =
        ref.watch(providerRecommendationsProvider(mangaId, providerName));
    final providers =
        ref.watch(recommendationSetupProvider(mangaId)).value?.providers ??
            const [];
    var title = providerName.split('|').first;
    for (final p in providers) {
      if (p.key == providerName) {
        title = p.name;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: recs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Emoticons(title: context.l10n.errorSomethingWentWrong),
        data: (list) => list.isEmpty
            ? Emoticons(title: context.l10n.noResultFound)
            : GridView.builder(
                padding: KEdgeInsets.a8.size,
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  childAspectRatio: 0.6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  return InkWell(
                    borderRadius: KBorderRadius.r8.radius,
                    onTap: () =>
                        GlobalSearchRoute(query: r.title).push(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: KBorderRadius.r8.radius,
                            child: r.coverUrl != null
                                ? Image.network(
                                    r.coverUrl!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(color: Colors.black26),
                                  )
                                : const ColoredBox(color: Colors.black26),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
