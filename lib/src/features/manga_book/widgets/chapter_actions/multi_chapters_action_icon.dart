// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import 'chapter_bulk_actions.dart';

class MultiChaptersActionIcon extends ConsumerWidget {
  const MultiChaptersActionIcon({
    this.iconData,
    required this.chapters,
    required this.change,
    required this.refresh,
    this.icon,
    super.key,
  });

  /// Full chapter data is needed for per-manga tracker sync and delete-on-manual-read across series.
  final List<ChapterDto> chapters;
  final ChapterChange change;
  final AsyncValueSetter<bool> refresh;
  final IconData? iconData;
  final Widget? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: icon ?? Icon(iconData),
      onPressed: () async {
        if (change.isRead != null) {
          await markChaptersRead(
            context: context,
            ref: ref,
            chapters: chapters,
            isRead: change.isRead!,
            refresh: refresh,
            resetPosition: change.lastPageRead == 0,
          );
          return;
        }
        final result = await AsyncValue.guard(
          () => ref
              .read(mangaBookRepositoryProvider)
              .modifyBulkChapters(
                ChapterBatch(
                  ids: [for (final c in chapters) c.id],
                  patch: change,
                ),
              ),
        );
        if (context.mounted) {
          result.showToastOnError(ref.read(toastProvider));
        }
        await refresh(true);
      },
    );
  }
}
