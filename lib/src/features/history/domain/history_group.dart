// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

import '../../../utils/extensions/custom_extensions.dart';
import 'history_item.dart';

part 'history_group.freezed.dart';

@freezed
abstract class HistoryGroup with _$HistoryGroup {
  const factory HistoryGroup({
    required String title,
    required List<HistoryItemDto> items,
  }) = _HistoryGroup;

  const HistoryGroup._();

  int get itemCount => items.length;

  bool get isEmpty => items.isEmpty;

  bool get isNotEmpty => items.isNotEmpty;

  DateTime? get mostRecentReadDate {
    if (items.isEmpty) return null;

    return items
        .where((item) => item.readAt != null)
        .map((item) => item.readAt!)
        .fold<DateTime?>(
            null,
            (previous, current) => previous == null
                ? current
                : DateTimeExtensions.max(previous, current));
  }

  String? getLastReadDescription(BuildContext context) {
    final lastRead = mostRecentReadDate;
    if (lastRead == null) return null;

    return lastRead.convertToDaysAgo(context);
  }

  String getLocalizedTitle(BuildContext context) {
    if (title == DateGroupKeys.today.value) {
      return context.l10n.today;
    } else if (title == DateGroupKeys.yesterday.value) {
      return context.l10n.yesterday;
    } else if (title == DateGroupKeys.recentlyRead.value) {
      return context.l10n.recentlyRead;
    }

    if (title.startsWith('week_')) {
      final weekdayNumber = int.tryParse(title.split('_')[1]);
      if (weekdayNumber != null && weekdayNumber >= 1 && weekdayNumber <= 7) {
        final now = DateTime.now();
        final daysToSubtract = (now.weekday - weekdayNumber) % 7;
        final targetDate = now.subtract(Duration(days: daysToSubtract));
        return targetDate.convertToDaysAgo(context);
      }
    }

    final parsedDate = _tryParseDate(title);
    if (parsedDate != null) {
      return parsedDate.convertToDaysAgo(context);
    }

    return title;
  }

  DateTime? _tryParseDate(String dateString) {
    try {
      return DateFormat.yMMMd().parse(dateString);
    } catch (_) {
      try {
        return DateFormat.yMd().parse(dateString);
      } catch (_) {
        return null;
      }
    }
  }

  HistoryGroup filterByQuery(String? query) {
    if (query == null || query.trim().isEmpty) return this;

    final filteredItems = items.where((HistoryItemDto item) {
      if (query.trim().isEmpty) return true;
      final searchQuery = query.toLowerCase();

      return item.manga.title.toLowerCase().contains(searchQuery) ||
          item.name.toLowerCase().contains(searchQuery) ||
          (item.manga.author?.toLowerCase().contains(searchQuery) ?? false) ||
          (item.scanlator?.toLowerCase().contains(searchQuery) ?? false);
    }).toList();
    return copyWith(items: filteredItems);
  }
}
