import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/webui_meta/webui_settings.dart';
import '../../../../offline/data/server_reachability.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../downloads/controller/downloads_controller.dart';
import '../../manga_details/controller/manga_details_controller.dart';

List<int> chapterIdsForDownloadAhead({
  required ChapterDto chapter,
  required List<ChapterDto> chapters,
  required ChapterDto? nextChapter,
  required int pageIndex,
  required int limit,
  required Set<int> queued,
}) {
  if (limit == 0 ||
      !chapter.user.isDownloaded ||
      chapter.pageCount <= 0 ||
      (pageIndex + 1) / chapter.pageCount <= 0.25) {
    return [];
  }
  if (nextChapter == null || !nextChapter.user.isDownloaded) return [];
  final index = chapters.indexWhere((item) => item.id == chapter.id);
  final nextIndex = chapters.indexWhere((item) => item.id == nextChapter.id);
  if (index < 0 || nextIndex < 0 || (nextIndex - index).abs() != 1) return [];
  final step = nextIndex - index;
  final ahead = <ChapterDto>[
    for (var i = nextIndex; i >= 0 && i < chapters.length; i += step)
      chapters[i],
  ];
  final selected = ahead
      .where((item) => !item.user.isRead)
      .take(limit)
      .map((item) => item.id)
      .toSet();
  return chapters
      .where(
        (item) =>
            selected.contains(item.id) &&
            !item.user.isDownloaded &&
            !queued.contains(item.id),
      )
      .map((item) => item.id)
      .toList();
}

final _downloadAheadPendingProvider = Provider<Set<int>>((ref) => {});

Future<void> downloadAhead(
  WidgetRef ref,
  int mangaId,
  int chapterId,
  int pageIndex, {
  String? readerScanlatorGroup,
}) async {
  if (ref.read(viewOfflineNowProvider) || ref.read(serverUnreachableProvider)) {
    return;
  }
  final limit = ref.read(downloadAheadLimitProvider);
  if (limit == 0) return;
  final chapters = ref
      .read(
        mangaChapterListWithFilterProvider(
          mangaId: mangaId,
          keepChapterId: chapterId,
          readerScanlatorGroup: readerScanlatorGroup,
        ),
      )
      .value;
  if (chapters == null) return;
  final chapter = chapters
      .where((chapter) => chapter.id == chapterId)
      .firstOrNull;
  if (chapter == null) return;
  final queue = ref.read(downloadsMapProvider);
  if (!ref.read(downloadStatusProvider).hasValue) return;
  final pending = ref.read(_downloadAheadPendingProvider);
  final ids = chapterIdsForDownloadAhead(
    chapter: chapter,
    chapters: chapters,
    nextChapter: ref
        .read(
          getNextAndPreviousChaptersProvider(
            mangaId: mangaId,
            chapterId: chapterId,
            readerScanlatorGroup: readerScanlatorGroup,
          ),
        )
        ?.first,
    pageIndex: pageIndex,
    limit: limit,
    queued: {...queue.keys, ...pending},
  );
  if (ids.isEmpty) return;
  pending.addAll(ids);
  try {
    await ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue(ids);
  } finally {
    pending.removeAll(ids);
  }
}

void watchDownloadAhead(WidgetRef ref) {
  if (ref.watch(downloadAheadLimitProvider) != 0) {
    ref.watch(downloadsMapProvider);
  }
}
