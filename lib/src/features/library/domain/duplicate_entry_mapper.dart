/// Snapshots a [MangaDto] into the matcher's plain-Dart [DupEntry] shape.
library;

import '../../manga_book/domain/manga/manga_model.dart';
import 'duplicate_matcher.dart';

DupEntry dupEntryFromManga(MangaDto manga) => (
  id: manga.id,
  title: manga.title,
  description: manga.description,
  trackerPairs: manga.trackRecords.nodes
      .map(
        (node) => (
          trackerId: node.trackerId,
          remoteId: node.remoteId,
          remoteTitle: node.title,
        ),
      )
      .toList(),
);
