
class ChapterDownloadCandidate {
  final int id;
  final double chapterNumber;
  final bool isRead;
  final bool isDownloaded;

  const ChapterDownloadCandidate({
    required this.id,
    required this.chapterNumber,
    required this.isRead,
    required this.isDownloaded,
  });
}

/// Order matches the bulk-download menu.
enum DownloadPreset {
  nextChapter,
  next5,
  next10,
  next25,
  unread,
  all,
}

/// "Next" walks forward from the highest read chapter, skipping downloads, regardless of display sort.
List<int> chaptersToQueueForPreset(
  List<ChapterDownloadCandidate> chapters,
  DownloadPreset preset,
) {
  final sorted = [...chapters]
    ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

  switch (preset) {
    case DownloadPreset.unread:
      return sorted
          .where((c) => !c.isRead && !c.isDownloaded)
          .map((c) => c.id)
          .toList();

    case DownloadPreset.all:
      return sorted
          .where((c) => !c.isDownloaded)
          .map((c) => c.id)
          .toList();

    case DownloadPreset.nextChapter:
    case DownloadPreset.next5:
    case DownloadPreset.next10:
    case DownloadPreset.next25:
      final n = switch (preset) {
        DownloadPreset.nextChapter => 1,
        DownloadPreset.next5 => 5,
        DownloadPreset.next10 => 10,
        DownloadPreset.next25 => 25,
        _ => 0,
      };

      final readChapters = sorted.where((c) => c.isRead);
      final readPosition = readChapters.isEmpty
          ? null
          : readChapters.last.chapterNumber;

      return sorted
          .where((c) =>
              readPosition == null || c.chapterNumber > readPosition)
          .where((c) => !c.isDownloaded)
          .take(n)
          .map((c) => c.id)
          .toList();
  }
}
