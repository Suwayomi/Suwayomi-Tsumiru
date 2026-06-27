// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';

class MultiChaptersActionIcon extends ConsumerWidget {
  const MultiChaptersActionIcon({
    this.iconData,
    required this.chapterList,
    required this.change,
    required this.refresh,
    this.icon,
    this.mangaId,
    super.key,
  });
  final List<int> chapterList;
  final ChapterChange change;
  final AsyncValueSetter<bool> refresh;
  final IconData? iconData;
  final Widget? icon;
  /// When non-null, fires [maybeTrackProgressOnReadFetch] after marking read.
  /// Pass only for single-manga contexts (e.g. the manga-details screen).
  /// Omit (null) for multi-manga contexts (e.g. the updates screen) where the
  /// chapters may belong to different manga.
  final int? mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: icon ?? Icon(iconData),
      onPressed: () async {
        final result = await AsyncValue.guard(
          () => ref.read(mangaBookRepositoryProvider).modifyBulkChapters(
                ChapterBatch(
                  ids: chapterList,
                  patch: change,
                ),
              ),
        );
        if (context.mounted) {
          result.showToastOnError(ref.read(toastProvider));
        }
        // Fire tracker sync when this is a mark-read action on a single manga.
        final isMarkRead = change.isRead == true;
        final id = mangaId;
        if (!result.hasError && isMarkRead && id != null) {
          unawaited(maybeTrackProgressOnReadFetch(
            ref,
            mangaId: id,
            isRead: true,
            manual: true,
          ));
          // Delete the on-device copies once read, if the user opted in.
          for (final cid in chapterList) {
            unawaited(maybeDeleteOnManualLocal(ref, chapterId: cid));
            unawaited(
                maybeDeleteOnManualServer(ref, mangaId: id, chapterId: cid));
          }
        }
        await refresh(true);
      },
    );
  }
}
