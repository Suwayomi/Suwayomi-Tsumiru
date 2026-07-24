// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/custom_checkbox_list_tile.dart';
import '../controller/manga_details_controller.dart';
import '../controller/scanlator_dedup.dart';
import 'scanlator_preference_dialog.dart';

class MangaChapterFilter extends ConsumerWidget {
  const MangaChapterFilter({super.key, required this.mangaId});
  final int mangaId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanlatorList =
        ref.watch(mangaScanlatorListProvider(mangaId: mangaId));
    final preferred =
        ref.watch(mangaPreferredScanlatorsProvider(mangaId: mangaId));
    final showAll =
        ref.watch(mangaShowAllScanlatorVersionsProvider(mangaId: mangaId));
    return ListView(
      children: [
        CustomCheckboxListTile(
          title: context.l10n.unread,
          provider: mangaChapterFilterUnreadProvider,
          onChanged: ref.read(mangaChapterFilterUnreadProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.bookmarked,
          provider: mangaChapterFilterBookmarkedProvider,
          onChanged:
              ref.read(mangaChapterFilterBookmarkedProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.downloaded,
          provider: mangaChapterFilterDownloadedProvider,
          onChanged:
              ref.read(mangaChapterFilterDownloadedProvider.notifier).update,
        ),
        // Unknown-inclusive: a series with one named group plus blanks still
        // needs the section, since Unknown must be rankable too.
        if (scanlatorList.length > 1) ...[
          ListTile(
            title: Text(
              context.l10n.scanlators,
              style: context.textTheme.labelLarge,
            ),
            dense: true,
          ),
          ListTile(
            title: Text(context.l10n.preferredScanlationGroups),
            subtitle: Text(
              preferred.isEmpty
                  ? context.l10n.noGroupPreference
                  : preferred
                      .map((g) => g == kUnknownScanlatorGroup
                          ? context.l10n.unknownScanlator
                          : g)
                      .join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => ScanlatorPreferenceDialog(mangaId: mangaId),
            ),
          ),
          SwitchListTile(
            title: Text(context.l10n.showAllChapterVersions),
            value: showAll,
            onChanged: preferred.isEmpty
                ? null
                : ref
                    .read(mangaShowAllScanlatorVersionsProvider(
                            mangaId: mangaId)
                        .notifier)
                    .update,
          ),
        ],
      ],
    );
  }
}
