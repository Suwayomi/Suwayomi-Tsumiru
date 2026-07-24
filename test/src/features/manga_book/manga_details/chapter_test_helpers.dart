// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';

Fragment$ChapterDto ch({
  required int id,
  required double number,
  String? scanlator,
  bool isRead = false,
  bool isDownloaded = false,
  bool isBookmarked = false,
  int lastPageRead = 0,
  int sourceOrder = 0,
}) =>
    Fragment$ChapterDto(
      id: id,
      mangaId: 1,
      name: 'Chapter $number',
      chapterNumber: number,
      sourceOrder: sourceOrder,
      isRead: isRead,
      isBookmarked: isBookmarked,
      isDownloaded: isDownloaded,
      lastPageRead: lastPageRead,
      pageCount: 10,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      scanlator: scanlator,
      meta: const [],
    );
