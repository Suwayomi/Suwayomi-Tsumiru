// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/cover_row_section.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../../offline/data/server_reachability.dart';
import '../../../../settings/presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../data/recommendations/recommendation_provider.dart';
import '../../../data/recommendations/recommendation_repository.dart';
import '../../recommends/recommendation_card.dart';
import '../../recommends/recommendation_loading.dart';

class RecommendsRow extends HookConsumerWidget {
  const RecommendsRow({super.key, required this.mangaId, this.mangaTitle});

  final int mangaId;
  final String? mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retry = useState(0);
    final credentials = ref.watch(authCredentialsStoreProvider).value;
    final server = ref.watch(serverUrlProvider);
    final snapshot = useMemoized(() => <Recommendation>[], [
      mangaId,
      server,
      credentials?.sessionEpoch,
      credentials?.sessionChanging,
      credentials?.accountBinding?.catalogId,
      credentials?.accountBinding?.userId,
      retry.value,
    ]);
    if (!ref.watch(showRecommendationsProvider).ifNull(true) ||
        ref.watch(recommendsInOverflowProvider).ifNull(false) ||
        ref.watch(serverUnreachableProvider) ||
        ref.watch(viewOfflineNowProvider)) {
      return const SizedBox.shrink();
    }
    final recs = ref.watch(mangaRecommendationsProvider(mangaId));
    if (snapshot.isEmpty && recs.asData?.value.isNotEmpty == true) {
      snapshot.addAll(recs.value!);
    }
    final list = snapshot.isEmpty ? null : snapshot;
    void refresh() {
      ref.invalidate(recommendationSetupProvider(mangaId));
      retry.value++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 0),
        LayoutBuilder(
          builder: (context, constraints) {
            final inner = constraints.maxWidth - 38;
            final whole = (inner / 106 - .5).floor().clamp(1, 100);
            final width = (inner - whole * 10) / (whole + .5);
            return CoverRowSection(
              title: context.l10n.suggestions,
              onSeeAll: () => RecommendsRoute(
                mangaId: mangaId,
                mangaTitle: mangaTitle,
              ).push(context),
              padding: const EdgeInsets.fromLTRB(19, 4, 19, 16),
              height: width * 1.5 + 42,
              itemCount: list?.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  RecommendationCard(rec: list![index], width: width),
              child: list == null
                  ? SizedBox(
                      height: width * 1.5 + 42,
                      child: recs.isLoading
                          ? const RecommendationLoading(explainServices: true)
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    recs.hasError
                                        ? context.l10n.suggestionsLoadFailed
                                        : context.l10n.suggestionsEmpty,
                                    textAlign: TextAlign.center,
                                    style: context.textTheme.bodyMedium,
                                  ),
                                  TextButton(
                                    onPressed: refresh,
                                    child: Text(context.l10n.retry),
                                  ),
                                ],
                              ),
                            ),
                    )
                  : null,
            );
          },
        ),
      ],
    );
  }
}
