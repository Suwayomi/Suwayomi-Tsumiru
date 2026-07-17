// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/manga_details_controller.dart';

/// Compact list/grid segmented toggle for the chapter-count header row.
class ChapterListModeToggle extends ConsumerWidget {
  const ChapterListModeToggle({super.key, required this.mangaId});
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.theme.colorScheme;
    final mode = ref.watch(mangaChapterListModeProvider(mangaId: mangaId));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in ChapterListMode.values)
            Tooltip(
              message: value.toLocale(context),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => ref
                    .read(mangaChapterListModeProvider(mangaId: mangaId)
                        .notifier)
                    .update(value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: mode == value
                        ? cs.primary.withValues(alpha: 0.18)
                        : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    value.icon,
                    size: 18,
                    color: mode == value ? cs.primary : cs.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
