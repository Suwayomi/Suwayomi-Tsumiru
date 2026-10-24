// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/navigation.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../data/recommendations/recommendation_repository.dart';
import 'recommendation_error_message.dart';
import 'recommendation_loading.dart';

class RecommendsBrowseScreen extends ConsumerWidget {
  const RecommendsBrowseScreen({
    super.key,
    required this.mangaId,
    required this.providerName,
  });

  final int mangaId;

  /// Uses name+category, since MangaUpdates shares a display name across two providers.
  final String providerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(
      providerRecommendationsProvider(mangaId, providerName),
    );
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
    final topBar = showsMergedTopBar(context);
    final barTitle = Text(title);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: barTitle,
            ),
      body: recs.when(
        loading: () => const RecommendationLoading(),
        error: (e, _) =>
            Emoticons(title: recommendationErrorMessage(context, e, title)),
        data: (list) => list.isEmpty
            ? Emoticons(title: context.l10n.noResultFound)
            : GridView.builder(
                padding: KEdgeInsets.a8.size,
                gridDelegate: const MangaCoverGridDelegate(
                  maxCrossAxisExtent: 120,
                  titleExtent: kRecommendsTitleExtent,
                  coverInset: 0,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  return InkWell(
                    borderRadius: KBorderRadius.r8.radius,
                    onTap: () => openGlobalSearch(
                      context,
                      query: r.title,
                      fromSuggestion: true,
                    ),
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
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: context
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                  )
                                : ColoredBox(
                                    color: context
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
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
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: barTitle,
      child: scaffold,
    );
  }
}
