// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/cover_row_section.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../data/recommendations/recommendation_provider.dart';
import '../../data/recommendations/recommendation_repository.dart';
import 'recommendation_card.dart';
import 'recommendation_error_message.dart';
import 'recommendation_loading.dart';

class RecommendsScreen extends ConsumerWidget {
  const RecommendsScreen({super.key, required this.mangaId, this.mangaTitle});

  final int mangaId;
  final String? mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(recommendationSetupProvider(mangaId));
    final topBar = showsMergedTopBar(context);
    final title = Text(
      mangaTitle != null
          ? context.l10n.similarTo(mangaTitle!)
          : context.l10n.recommendations,
    );
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
            ),
      body: setup.when(
        loading: () => const RecommendationLoading(),
        error: (_, _) => Emoticons(title: context.l10n.errorSomethingWentWrong),
        data: (value) {
          final providers = value?.providers ?? const [];
          if (providers.isEmpty) {
            return Emoticons(title: context.l10n.noRecommendationsForTitle);
          }
          // Keep empty/error sections, rank results first, and preserve keys so reordering cannot reload providers.
          int rankOf(RecommendationProvider p) {
            final recs = ref.watch(
              providerRecommendationsProvider(mangaId, p.key),
            );
            if (recs.hasError) return 2;
            if (recs.hasValue) return recs.value!.isEmpty ? 2 : 0;
            return 1;
          }

          final ordered =
              [for (var i = 0; i < providers.length; i++) (i, providers[i])]
                ..sort((a, b) {
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
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}

class _ProviderSection extends ConsumerWidget {
  const _ProviderSection({
    super.key,
    required this.mangaId,
    required this.provider,
  });

  final int mangaId;
  final RecommendationProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(
      providerRecommendationsProvider(mangaId, provider.key),
    );
    Widget section({
      int? itemCount,
      IndexedWidgetBuilder? itemBuilder,
      Widget? child,
    }) => CoverRowSection(
      title: provider.name,
      subtitle: provider.category,
      onSeeAll: () => RecommendsBrowseRoute(
        mangaId: mangaId,
        providerName: provider.key,
      ).push(context),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 200,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        recs.when(
          loading: () => section(
            child: const SizedBox(
              height: 200,
              child: RecommendationLoading(),
            ),
          ),
          error: (e, _) => section(
            child: _SectionMessage(
              recommendationErrorMessage(context, e, provider.name),
            ),
          ),
          data: (list) => list.isEmpty
              ? section(child: _SectionMessage(context.l10n.noResultFound))
              : section(
                  itemCount: list.length,
                  itemBuilder: (context, i) => RecommendationCard(rec: list[i]),
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.info_24_regular, color: context.theme.hintColor),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
