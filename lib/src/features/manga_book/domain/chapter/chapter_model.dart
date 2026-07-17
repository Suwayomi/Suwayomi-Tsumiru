// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:intl/intl.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'graphql/__generated__/fragment.graphql.dart';

typedef ChapterDto = Fragment$ChapterDto;

// Matches Komikku's formatter: up to 3 decimals, trailing zeros dropped.
final _chapterNumberFormat = NumberFormat('#.###', 'en_US');

typedef ChapterWithMangaDto = Fragment$ChapterWithMangaDto;

extension ChapterExtension on Fragment$ChapterDto {
  bool query([String? query]) {
    return name.query(query) || index == int.tryParse(query ?? '');
  }

  int get index => sourceOrder;

  String get formattedChapterNumber =>
      _chapterNumberFormat.format(chapterNumber);

  bool get hasReadingProgress =>
      isRead || lastPageRead > 0 || lastReadAt != '0';

  Map<String, String> get metaData =>
      {for (final metaItem in meta) metaItem.key: metaItem.value};
}
