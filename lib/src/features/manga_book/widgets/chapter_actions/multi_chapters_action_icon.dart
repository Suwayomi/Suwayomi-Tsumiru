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
import '../../../offline/data/offline_repository.dart';
import '../../../tracking/domain/track_progress_gate.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import '../../presentation/manga_details/controller/scanlator_propagation.dart';

class MultiChaptersActionIcon extends ConsumerWidget {
  const MultiChaptersActionIcon({
    this.iconData,
    required this.chapters,
    required this.change,
    required this.refresh,
    this.icon,
    super.key,
  });

  /// The selected chapters. Carrying the full [ChapterDto] (not just ids) lets
  /// a mark-read sync each affected manga to its tracker and honour the
  /// delete-on-manual-read setting per chapter — correctly even when the
  /// selection spans multiple manga (e.g. the updates screen).
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
        final ids = [for (final c in chapters) c.id];
        // Read/unread expands to every scanlator duplicate; other patches
        // stay per-copy.
        final expandedByManga = <int, List<int>>{
          if (change.isRead != null)
            for (final mangaId in {for (final c in chapters) c.mangaId})
              mangaId: expandIdsAcrossScanlators(
                ref,
                mangaId: mangaId,
                chapterIds: [
                  for (final c in chapters)
                    if (c.mangaId == mangaId) c.id,
                ],
              ),
        };
        final idsForWrite = change.isRead == null
            ? ids
            : [for (final l in expandedByManga.values) ...l];
        final bool ok;
        if (change.isRead != null) {
          // Read/unread goes through the offline-aware write-through path: the
          // local row is updated first (so it survives offline + restart and
          // keeps Resume truthful), then the server. A failure with offline
          // active is queued, not lost, so only surface an error when there's
          // no local fallback.
          ok = await recordReadState(
            ref,
            chapterIds: idsForWrite,
            isRead: change.isRead!,
            // Also true on mark-unread — stale progress there still reads
            // as in-progress.
            resetPosition: change.lastPageRead == 0,
          );
          if (!ok && context.mounted && !ref.read(offlineActiveProvider)) {
            ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
          }
        } else {
          final result = await AsyncValue.guard(
            () => ref.read(mangaBookRepositoryProvider).modifyBulkChapters(
                  ChapterBatch(ids: idsForWrite, patch: change),
                ),
          );
          if (context.mounted) {
            result.showToastOnError(ref.read(toastProvider));
          }
          ok = !result.hasError;
        }
        // On a successful mark-read, sync each affected manga to its tracker and
        // honour the delete-on-manual-read setting — keyed off each chapter's
        // own mangaId, so a multi-manga selection (updates screen) syncs them
        // all instead of being silently skipped.
        if (ok && change.isRead == true) {
          for (final mangaId in {for (final c in chapters) c.mangaId}) {
            unawaited(maybeTrackProgressOnReadFetch(
              ref,
              mangaId: mangaId,
              isRead: true,
              manual: true,
            ));
          }
          // Expanded set: hidden duplicates get delete-on-manual-read too.
          for (final entry in expandedByManga.entries) {
            for (final id in entry.value) {
              unawaited(maybeDeleteOnManualLocal(ref, chapterId: id));
              unawaited(maybeDeleteOnManualServer(ref,
                  mangaId: entry.key, chapterId: id));
            }
          }
        }
        await refresh(true);
      },
    );
  }
}
