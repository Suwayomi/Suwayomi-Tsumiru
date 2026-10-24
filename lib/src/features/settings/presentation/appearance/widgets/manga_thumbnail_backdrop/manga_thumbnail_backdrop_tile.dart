// Copyright (c) 2026 Contributors to the Suwayomi project
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
import '../../../../../../widgets/compact_switch.dart';

part 'manga_thumbnail_backdrop_tile.g.dart';

@riverpod
class MangaThumbnailBackdrop extends _$MangaThumbnailBackdrop
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaThumbnailBackdrop);
}

bool resolveMangaThumbnailBackdrop({
  required bool? override,
  required bool twoColumn,
}) => override ?? !twoColumn;

class MangaThumbnailBackdropTile extends ConsumerWidget {
  const MangaThumbnailBackdropTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoColumn = context.windowSizeClass >= WindowSizeClass.expanded;
    return CompactSwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(context.l10n.mangaThumbnailBackdrop),
      onChanged: ref.read(mangaThumbnailBackdropProvider.notifier).update,
      value: resolveMangaThumbnailBackdrop(
        override: ref.watch(mangaThumbnailBackdropProvider),
        twoColumn: twoColumn,
      ),
    );
  }
}
