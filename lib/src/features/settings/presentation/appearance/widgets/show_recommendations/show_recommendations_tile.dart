// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'show_recommendations_tile.g.dart';

@riverpod
class ShowRecommendations extends _$ShowRecommendations
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showRecommendations);
}

@riverpod
class RecommendsInOverflow extends _$RecommendsInOverflow
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.recommendsInOverflow);
}

class ShowRecommendationsTile extends ConsumerWidget {
  const ShowRecommendationsTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.recommend_rounded),
      title: Text(context.l10n.showRecommendations),
      subtitle: Text(context.l10n.showRecommendationsSubtitle),
      onChanged: ref.read(showRecommendationsProvider.notifier).update,
      value: ref.watch(showRecommendationsProvider).ifNull(true),
    );
  }
}

class RecommendsInOverflowTile extends ConsumerWidget {
  const RecommendsInOverflowTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showRecommendationsProvider).ifNull(true)) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.more_vert_rounded),
      title: Text(context.l10n.recommendsInOverflow),
      subtitle: Text(context.l10n.recommendsInOverflowSubtitle),
      onChanged: ref.read(recommendsInOverflowProvider.notifier).update,
      value: ref.watch(recommendsInOverflowProvider).ifNull(false),
    );
  }
}
