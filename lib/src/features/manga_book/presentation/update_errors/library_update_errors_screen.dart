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
import '../../../../utils/theme/brand.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/manga_cover/list/manga_cover_list_tile.dart';
import '../../../migration/domain/migration_models.dart';
import '../../data/updates/updates_repository.dart';

class LibraryUpdateErrorsScreen extends ConsumerWidget {
  const LibraryUpdateErrorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(failedUpdatesProvider);
    final count = failed.value?.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(count == null
            ? context.l10n.libraryUpdateErrors
            : context.l10n.libraryUpdateErrorsCount(count)),
      ),
      body: failed.showUiWhenData(
        context,
        (mangas) => RefreshIndicator(
          onRefresh: () => ref.refresh(failedUpdatesProvider.future),
          child: mangas.isEmpty
              ? Stack(
                  children: [
                    ListView(),
                    Emoticons(
                      title: context.l10n.libraryUpdateErrorsEmpty,
                      subTitle: context.l10n.libraryUpdateErrorsEmptyDetail,
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: mangas.length,
                  itemBuilder: (context, index) {
                    final manga = mangas[index];
                    return MangaCoverListTile(
                      manga: manga,
                      onPressed: () => MangaRoute(mangaId: manga.id).push(context),
                      trailing: _MigrateButton(
                        onPressed: () => MigrationBulkConfigRoute(
                          $extra: MigrationBulkConfigData(mangaIds: [manga.id]),
                        ).push(context),
                      ),
                    );
                  },
                ),
        ),
        refresh: () => ref.invalidate(failedUpdatesProvider),
      ),
    );
  }
}

/// A pill button that sends a series into the migration flow — a failed update
/// often means the source is gone, and swapping it is the fix.
class _MigrateButton extends StatelessWidget {
  const _MigrateButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final accent = brandBrightAccent(cs);
    return Padding(
      padding: KEdgeInsets.h8.size,
      child: Material(
        color: cs.primary.withValues(alpha: 0.14),
        shape: StadiumBorder(
          side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 17, color: accent),
                const SizedBox(width: 6),
                Text(
                  context.l10n.migrate,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
