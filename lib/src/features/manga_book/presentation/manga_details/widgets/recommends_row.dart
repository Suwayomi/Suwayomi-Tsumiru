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
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../offline/data/server_reachability.dart';
import '../../../../settings/presentation/appearance/widgets/show_recommendations/show_recommendations_tile.dart';
import '../../../data/recommendations/recommendation_repository.dart';
import '../../recommends/recommendation_card.dart';

class RecommendsRow extends HookConsumerWidget {
  const RecommendsRow({super.key, required this.mangaId, this.mangaTitle});

  final int mangaId;
  final String? mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useScrollController();
    final rebuild = useState(0);
    useEffect(() {
      void onScroll() => rebuild.value++;
      controller.addListener(onScroll);
      return () => controller.removeListener(onScroll);
    }, [controller]);
    if (!ref.watch(showRecommendationsProvider).ifNull(true) ||
        ref.watch(recommendsInOverflowProvider).ifNull(false) ||
        ref.watch(serverUnreachableProvider) ||
        ref.watch(viewOfflineNowProvider)) {
      return const SizedBox.shrink();
    }
    final recs = ref.watch(mangaRecommendationsProvider(mangaId));
    if (recs.hasError || (recs.hasValue && recs.value!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final position = controller.hasClients ? controller.position : null;
    final offset = position?.pixels ?? 0;
    final maxExtent = position?.maxScrollExtent ?? 0;
    void scrollBy(int direction) {
      final position = controller.position;
      final target =
          (position.pixels + direction * position.viewportDimension * .8).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
      if (context.reduceMotion) {
        controller.jumpTo(target);
      } else {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    Widget arrow(bool left) {
      final enabled = left ? offset > 0 : offset < maxExtent;
      return Opacity(
        opacity: enabled ? 1 : .4,
        child: IconButton.outlined(
          tooltip: left ? context.l10n.back : context.l10n.next,
          onPressed: enabled ? () => scrollBy(left ? -1 : 1) : null,
          icon: Icon(
            left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            size: 20,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(34),
            maximumSize: const Size.square(34),
            padding: EdgeInsets.zero,
            foregroundColor: context.colorScheme.onSurface,
            backgroundColor: context.colorScheme.surfaceContainer,
            side: BorderSide(color: context.colorScheme.outlineVariant),
            shape: const CircleBorder(),
          ),
        ),
      );
    }

    void openSeeAll() =>
        RecommendsRoute(mangaId: mangaId, mangaTitle: mangaTitle).push(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 0),
        if (context.isTablet)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.suggestions,
                    style: context.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: openSeeAll,
                  child: Text(context.l10n.seriesSeeAll),
                ),
                const SizedBox(width: 10),
                arrow(true),
                const SizedBox(width: 8),
                arrow(false),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Tooltip(
              message: context.l10n.seriesSeeAll,
              child: InkWell(
                onTap: openSeeAll,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.suggestions,
                        style: context.textTheme.titleMedium,
                      ),
                    ),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 4, 19, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final whole = (constraints.maxWidth / 106 - .5).floor().clamp(
                1,
                100,
              );
              final width = (constraints.maxWidth - whole * 10) / (whole + .5);
              return SizedBox(
                height: width * 1.5 + 42,
                child: recs.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) =>
                      NotificationListener<ScrollMetricsNotification>(
                        onNotification: (_) {
                          rebuild.value++;
                          return false;
                        },
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => LinearGradient(
                            colors: const [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, (1 - 40 / bounds.width).clamp(0, 1), 1],
                          ).createShader(bounds),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: ListView.separated(
                              controller: controller,
                              scrollDirection: Axis.horizontal,
                              itemCount: list.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) =>
                                  RecommendationCard(
                                    rec: list[index],
                                    width: width,
                                  ),
                            ),
                          ),
                        ),
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
