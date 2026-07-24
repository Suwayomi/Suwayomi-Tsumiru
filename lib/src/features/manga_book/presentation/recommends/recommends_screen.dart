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
import '../../data/recommendations/recommendation_provider.dart';
import '../../data/recommendations/recommendation_repository.dart';
import 'recommendation_card.dart';

/// Komikku's RecommendsScreen: "Similar to {title}", one section per provider,
/// each loading, erroring, and emptying on its own.
class RecommendsScreen extends ConsumerWidget {
  const RecommendsScreen({super.key, required this.mangaId, this.mangaTitle});

  final int mangaId;
  final String? mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(recommendationSetupProvider(mangaId));
    return Scaffold(
      appBar: AppBar(
        title: Text(mangaTitle != null
            ? context.l10n.similarTo(mangaTitle!)
            : context.l10n.recommendations),
      ),
      body: setup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Emoticons(title: context.l10n.errorSomethingWentWrong),
        data: (value) {
          final providers = value?.providers ?? const [];
          if (providers.isEmpty) {
            return Emoticons(title: context.l10n.noRecommendationsForTitle);
          }
          // Komikku shows every applicable provider — each renders its own
          // results, "No results found", or error; sections never drop out.
          // Sink sources that resolved empty or errored below ones with results
          // (still-loading stay in the middle); keep original order within a
          // rank, and key each section so a reorder doesn't reload it.
          int rankOf(RecommendationProvider p) {
            final recs =
                ref.watch(providerRecommendationsProvider(mangaId, p.key));
            if (recs.hasError) return 2;
            if (recs.hasValue) return recs.value!.isEmpty ? 2 : 0;
            return 1;
          }

          final ordered = [
            for (var i = 0; i < providers.length; i++) (i, providers[i])
          ]..sort((a, b) {
              final r = rankOf(a.$2).compareTo(rankOf(b.$2));
              return r != 0 ? r : a.$1.compareTo(b.$1);
            });
          return ListView(
            children: [
              for (final e in ordered)
                _ProviderSection(
                  key: ValueKey(e.$2.key),
                  mangaId: mangaId,
                  provider: e.$2,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProviderSection extends ConsumerWidget {
  const _ProviderSection(
      {super.key, required this.mangaId, required this.provider});

  final int mangaId;
  final RecommendationProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs =
        ref.watch(providerRecommendationsProvider(mangaId, provider.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => RecommendsBrowseRoute(
            mangaId: mangaId,
            providerName: provider.key,
          ).push(context),
          child: Padding(
            padding: KEdgeInsets.h16v8.size,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.name,
                          style: context.textTheme.titleMedium),
                      Text(
                        provider.category,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: context.theme.hintColor),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ),
        recs.when(
          loading: () => const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => _SectionMessage(
            e is RecommendationHttpException
                ? context.l10n.httpErrorCheckWebView(e.statusCode)
                : context.l10n.errorSomethingWentWrong,
          ),
          data: (list) => list.isEmpty
              ? _SectionMessage(context.l10n.noResultFound)
              : SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) =>
                        RecommendationCard(rec: list[i]),
                  ),
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Komikku's per-section empty/error state: a centered info icon over a short
/// message, in place of the cover row.
class _SectionMessage extends StatelessWidget {
  const _SectionMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, color: context.theme.hintColor),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
