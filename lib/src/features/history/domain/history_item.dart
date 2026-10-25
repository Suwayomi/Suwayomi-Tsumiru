// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../data/graphql/__generated__/query.graphql.dart';

typedef HistoryItemDto = Fragment$HistoryChapterDto;

extension HistoryMangaCover on Fragment$HistoryChapterDto$manga {
  String get displayCoverUrl => resolveDisplayCover(
    thumbnailUrl: thumbnailUrl,
    meta: meta.map((m) => (key: m.key, value: m.value)),
  );

  String? get coverVersion =>
      displayCoverUrl == thumbnailUrl ? thumbnailUrlLastFetched : null;
}

extension HistoryItemExtension on HistoryItemDto {
  DateTime? get readAt => user.lastReadAt.parseTimestamp;

  bool get isReadToday {
    final readDate = readAt;
    if (readDate == null) return false;
    return readDate.isToday;
  }

  bool get isReadYesterday {
    final readDate = readAt;
    if (readDate == null) return false;
    return readDate.isYesterday;
  }

  String readDateGroup(BuildContext context) {
    final readDate = readAt;
    if (readDate == null) {
      return DateGroupKeys.recentlyRead.toLocale(context);
    }

    return readDate.dateGroupString(context);
  }

  String get readDateGroupKey {
    final readDate = readAt;
    if (readDate == null) {
      return DateGroupKeys.recentlyRead.value;
    }

    return readDate.dateGroupKey;
  }

  bool historyQuery([String? query]) {
    if (query.isBlank) return true;
    final searchQuery = query!.toLowerCase();

    return manga.title.toLowerCase().contains(searchQuery) ||
        name.toLowerCase().contains(searchQuery) ||
        (manga.author?.toLowerCase().contains(searchQuery) ?? false) ||
        (scanlator?.toLowerCase().contains(searchQuery) ?? false);
  }
}
