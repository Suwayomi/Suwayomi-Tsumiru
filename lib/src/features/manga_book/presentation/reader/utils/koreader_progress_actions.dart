import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../../offline/data/server_reachability.dart';
import '../../../../settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../controller/reader_controller.dart';

bool koSyncOnline(WidgetRef ref) =>
    !ref.read(viewOfflineNowProvider) && !ref.read(serverUnreachableProvider);

Future<void> applyKoSyncConflict({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterDto chapter,
  required int remotePage,
  required String deviceName,
  int? pageCount,
  ValueChanged<int>? onJump,
}) async {
  if (!koSyncOnline(ref)) return;
  final count = pageCount ?? chapter.pageCount;
  if (count <= 0) return;
  final page = remotePage.clamp(0, count - 1);
  final accept = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(context.l10n.koSyncLocationPrompt(page + 1, deviceName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
  if (accept != true || !context.mounted || !koSyncOnline(ref)) return;
  final complete = page == count - 1;
  final result = await recordReadingProgress(
    ref,
    mangaId: chapter.mangaId,
    chapterId: chapter.id,
    lastPageRead: complete ? 0 : page,
    isRead: complete,
  );
  if (!context.mounted) return;
  if (result.hasError) {
    ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
    return;
  }
  onJump?.call(page);
  ref.invalidate(chapterProvider(chapterId: chapter.id));
}

Future<void> syncKoReaderChapter({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterDto chapter,
  required bool push,
  int? pageCount,
  int? currentPage,
  ValueChanged<int>? onJump,
}) async {
  if (!koSyncOnline(ref)) return;
  try {
    final repository = ref.read(koreaderSyncRepositoryProvider);
    if (push) {
      final count = pageCount ?? chapter.pageCount;
      if (currentPage != null && count > 0) {
        final page = currentPage.clamp(0, count - 1);
        final complete = page == count - 1;
        final saved = await recordReadingProgress(
          ref,
          mangaId: chapter.mangaId,
          chapterId: chapter.id,
          lastPageRead: complete ? 0 : page,
          isRead: complete,
        );
        if (saved.hasError) throw saved.error!;
      }
      if (!context.mounted || !koSyncOnline(ref)) return;
      await repository.pushProgress(chapter.id);
      return;
    }
    final result = await repository.pullProgress(chapter.id);
    if (!context.mounted || !koSyncOnline(ref)) return;
    final conflict = result?.syncConflict;
    if (conflict != null) {
      await applyKoSyncConflict(
        context: context,
        ref: ref,
        chapter: chapter,
        remotePage: conflict.remotePage,
        deviceName: conflict.deviceName,
        pageCount: pageCount,
        onJump: onJump,
      );
    } else if (result?.chapter case final updated?) {
      final count = pageCount ?? updated.pageCount;
      if (count > 0) {
        onJump?.call(updated.user.lastPageRead.clamp(0, count - 1));
      }
      ref.invalidate(chapterProvider(chapterId: chapter.id));
    }
  } catch (_) {
    if (context.mounted) {
      ref.read(toastProvider)?.showError(context.l10n.errorSomethingWentWrong);
    }
  }
}
