// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../features/account/data/account_providers.dart';
import '../../../../features/offline/data/offline_download_providers.dart';
import '../../../../features/offline/data/offline_repository.dart';
import '../../../../features/tracking/domain/track_progress_gate.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/confirm_bulk_download_dialog.dart';
import '../../data/downloads/downloads_repository.dart';
import '../../data/manga_book/manga_book_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_batch/chapter_batch_model.dart';
import '../../domain/downloads/downloads_model.dart';
import '../../presentation/manga_details/controller/scanlator_propagation.dart';

Future<void> markChaptersRead({
  required BuildContext context,
  required WidgetRef ref,
  required List<ChapterDto> chapters,
  required bool isRead,
  required AsyncValueSetter<bool> refresh,
  bool resetPosition = true,
  bool showUndoToast = true,
}) async {
  if (chapters.isEmpty) return;
  final containerRead = ProviderScope.containerOf(context, listen: false).read;
  final expandedByManga = <int, List<int>>{
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
  final idsForWrite = [for (final l in expandedByManga.values) ...l];
  final toast = ref.read(toastProvider);
  final markedMessage = isRead
      ? context.l10n.markedAsRead(chapters.length)
      : context.l10n.markedAsUnread(chapters.length);
  final undoLabel = context.l10n.undo;
  final ok = await recordReadState(
    ref,
    chapterIds: idsForWrite,
    isRead: isRead,
    resetPosition: resetPosition,
  );
  if (!ok && context.mounted && !ref.read(offlineActiveProvider)) {
    ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
  }
  if (isRead) {
    for (final entry in expandedByManga.entries) {
      for (final id in entry.value) {
        unawaited(maybeDeleteOnManualLocal(containerRead, chapterId: id));
      }
    }
  }
  if (ok && isRead) {
    for (final mangaId in {for (final c in chapters) c.mangaId}) {
      unawaited(
        maybeTrackProgressOnReadFetch(
          containerRead,
          mangaId: mangaId,
          isRead: true,
          manual: true,
        ),
      );
    }
    for (final entry in expandedByManga.entries) {
      for (final id in entry.value) {
        unawaited(
          maybeDeleteOnManualServer(
            containerRead,
            mangaId: entry.key,
            chapterId: id,
          ),
        );
      }
    }
  }
  if (ok && showUndoToast && context.mounted) {
    toast?.showWithAction(
      markedMessage,
      actionLabel: undoLabel,
      onAction: () {
        if (!ref.context.mounted) return;
        unawaited(
          markChaptersRead(
            context: context,
            ref: ref,
            chapters: chapters,
            isRead: !isRead,
            refresh: refresh,
            resetPosition: resetPosition,
            showUndoToast: false,
          ),
        );
      },
    );
  }
  await refresh(true);
}

List<ChapterDto> previousChapters(
  List<ChapterDto> bulkList,
  ChapterDto anchor,
) => [
  for (final c in bulkList)
    if (c.mangaId == anchor.mangaId && c.index < anchor.index) c,
];

Future<void> markPreviousAsRead({
  required BuildContext context,
  required WidgetRef ref,
  required List<ChapterDto> bulkList,
  required ChapterDto anchor,
  required AsyncValueSetter<bool> refresh,
}) => markChaptersRead(
  context: context,
  ref: ref,
  chapters: previousChapters(bulkList, anchor),
  isRead: true,
  refresh: refresh,
);

Future<void> setChaptersBookmark({
  required WidgetRef ref,
  required List<ChapterDto> chapters,
  required bool isBookmarked,
  required AsyncValueSetter<bool> refresh,
}) async {
  if (chapters.isEmpty) return;
  final result = await AsyncValue.guard(
    () => ref
        .read(mangaBookRepositoryProvider)
        .modifyBulkChapters(
          ChapterBatch(
            ids: [for (final c in chapters) c.id],
            patch: ChapterChange(isBookmarked: isBookmarked),
          ),
        ),
  );
  result.showToastOnError(ref.read(toastProvider));
  await refresh(true);
}

Future<void> toggleChapterBookmark(WidgetRef ref, ChapterDto chapter) =>
    recordBookmark(
      ref,
      chapterId: chapter.id,
      isBookmarked: !chapter.isBookmarked.ifNull(),
    );

Future<void> keepChapterOffline(WidgetRef ref, int chapterId) =>
    saveChapterToDevice(ref, chapterId);

Future<void> removeChapterFromDevice(WidgetRef ref, int chapterId) =>
    deleteChapterFromDevice(ref, chapterId);

Future<void> keepChaptersOffline({
  required BuildContext context,
  required WidgetRef ref,
  required List<ChapterDto> chapters,
  required AsyncValueSetter<bool> refresh,
}) async {
  if (chapters.isEmpty) return;
  if (chapters.length > kBulkDownloadConfirmThreshold &&
      !await confirmBulkDownload(
        context,
        summary: '${chapters.length} chapters',
        toDevice: true,
      )) {
    return;
  }
  var failures = 0;
  for (final chapter in chapters) {
    try {
      await saveChapterToDevice(ref, chapter.id);
    } catch (_) {
      failures++;
    }
  }
  if (failures > 0 && context.mounted) {
    ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
  }
  await refresh(true);
}

Future<void> queueServerDownload({
  required BuildContext context,
  required WidgetRef ref,
  required List<int> chapterIds,
  required AsyncValueSetter<bool> refresh,
}) async {
  if (chapterIds.isEmpty) return;
  if (chapterIds.length > kBulkDownloadConfirmThreshold &&
      !await confirmBulkDownload(
        context,
        summary: '${chapterIds.length} chapters',
        toDevice: false,
      )) {
    return;
  }
  final result = await AsyncValue.guard(
    () => ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(chapterIds),
  );
  if (context.mounted) {
    if (result.hasError) {
      result.showToastOnError(ref.read(toastProvider));
    } else {
      ref.read(toastProvider)?.show(context.l10n.queued);
    }
  }
  await refresh(false);
}

/// Phone swipe's Download action, per live server state (Komikku parity):
/// queue when missing, cancel while queued/downloading, delete once the
/// server holds it. The delete follows the row icon: direct, no confirmation.
Future<void> runChapterSwipeDownload({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterDto chapter,
  required DownloadDto? queueEntry,
  required AsyncValueSetter<bool> refresh,
}) async {
  if (!canDownloadChapters(ref)) return;
  final toast = ref.read(toastProvider);
  if (queueEntry != null &&
      (queueEntry.state == DownloadState.QUEUED ||
          queueEntry.state == DownloadState.DOWNLOADING)) {
    final result = await AsyncValue.guard(
      () => ref
          .read(downloadsRepositoryProvider)
          .removeChapterFromDownloadQueue(chapter.id),
    );
    if (context.mounted) result.showToastOnError(toast);
  } else if (queueEntry != null) {
    final repo = ref.read(downloadsRepositoryProvider);
    final result = await AsyncValue.guard(() async {
      await repo.removeChapterFromDownloadQueue(chapter.id);
      await repo.addChaptersBatchToDownloadQueue([chapter.id]);
    });
    if (context.mounted) {
      if (result.hasError) {
        result.showToastOnError(toast);
      } else {
        toast?.show(context.l10n.queued);
      }
    }
  } else if (chapter.isDownloaded.ifNull()) {
    final containerRead = ProviderScope.containerOf(
      context,
      listen: false,
    ).read;
    final deleteIds = expandIdsAcrossScanlators(
      ref,
      mangaId: chapter.mangaId,
      chapterIds: [chapter.id],
    );
    final result = await AsyncValue.guard(
      () => ref.read(mangaBookRepositoryProvider).deleteChapters(deleteIds),
    );
    if (context.mounted) result.showToastOnError(toast);
    if (!result.hasError) {
      await cascadeServerDeleteToDevice(containerRead, deleteIds);
    }
  } else {
    await queueServerDownload(
      context: context,
      ref: ref,
      chapterIds: [chapter.id],
      refresh: refresh,
    );
    return;
  }
  await refresh(false);
}

Future<bool> deleteChaptersFromServerWithConfirm({
  required BuildContext context,
  required WidgetRef ref,
  required List<ChapterDto> chapters,
}) async {
  if (chapters.isEmpty) return false;
  final containerRead = ProviderScope.containerOf(context, listen: false).read;
  final repo = ref.read(offlineActiveProvider)
      ? ref.read(offlineRepositoryProvider)
      : null;
  final deleteIds = <int>[
    for (final entry in {for (final c in chapters) c.mangaId: true}.keys)
      ...expandIdsAcrossScanlators(
        ref,
        mangaId: entry,
        chapterIds: [
          for (final c in chapters)
            if (c.mangaId == entry) c.id,
        ],
      ),
  ];
  final onDevice =
      await repo?.deviceDownloadedCount([for (final c in chapters) c.id]) ?? 0;
  if (!context.mounted) return false;
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.delete),
          content: Text(
            [
              ctx.l10n.deleteChaptersConfirm,
              if (onDevice > 0) ctx.l10n.offlineBulkDeleteWarning(onDevice),
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.delete),
            ),
          ],
        ),
        animationStyle: context.motionStyle,
      ) ??
      false;
  if (!ok) return false;
  final result = await AsyncValue.guard(
    () => ref.read(mangaBookRepositoryProvider).deleteChapters(deleteIds),
  );
  if (context.mounted) {
    result.showToastOnError(ref.read(toastProvider));
  }
  if (!result.hasError) {
    await cascadeServerDeleteToDevice(containerRead, deleteIds);
  }
  return !result.hasError;
}

void openChapterInBrowser(
  BuildContext context,
  WidgetRef ref,
  ChapterDto chapter,
  String? seriesUrl,
) {
  final url = chapter.realUrl ?? seriesUrl;
  if (url == null) return;
  launchUrlInWeb(context, url, ref.read(toastProvider));
}

bool chapterHasBrowserTarget(ChapterDto chapter, String? seriesUrl) =>
    chapter.realUrl != null || seriesUrl != null;

bool canDownloadChapters(WidgetRef ref) => ref
    .read(settledAccountAccessProvider)
    .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
