// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../constants/enum.dart';
import '../../../../features/library/domain/library_search_query.dart';
import '../../../../utils/webui_meta/webui_meta_codec.dart';
import 'graphql/__generated__/fragment.graphql.dart';

part 'manga_model.freezed.dart';
part 'manga_model.g.dart';

typedef MangaDto = Fragment$MangaDto;

typedef MangaBaseDto = Fragment$MangaBaseDto;

extension LastReadChapterProgress on Fragment$MangaDto$user$lastReadChapter {
  bool get hasReadingProgress =>
      user.isRead || user.lastPageRead > 0 || user.lastReadAt != '0';
}

extension MangaExtensions on MangaDto {
  MangaMeta get metaData => MangaMeta.fromJson({
    for (final metaItem in meta) metaItem.key: metaItem.value,
  });

  int get readChapterCount => chapters.totalCount - user.unreadCount;

  String? get webUiNotes =>
      readWebUiValue({for (final m in meta) m.key: m.value}, 'notes');

  String get displayCoverUrl => resolveDisplayCover(
    thumbnailUrl: thumbnailUrl,
    meta: meta.map((m) => (key: m.key, value: m.value)),
  );

  /// Version for the server cover cache key; null for custom covers, which key by URL or path.
  String? get coverVersion =>
      displayCoverUrl == thumbnailUrl ? thumbnailUrlLastFetched : null;

  /// Suwayomi Local source ID "0" already holds server files, so server downloads do not apply.
  bool get isLocalSource => sourceId == '0';

  /// Matches the library search DSL; list filtering should parse the query once.
  bool query([String? query]) =>
      LibrarySearchQuery.parse(query).matches(filterFields());

  /// [trackerNames] resolves `tracked:<service>`; an empty map supports only the boolean tracked: form.
  LibraryFilterFields filterFields([Map<int, String> trackerNames = const {}]) {
    final m = metaData;
    return LibraryFilterFields(
      title: title,
      author: author,
      artist: artist,
      sourceId: sourceId,
      description: description,
      genres: genre.toList(),
      unreadCount: user.unreadCount,
      downloadCount: user.downloadCount,
      rating: m.rating,
      userTags: m.userTags ?? const [],
      status: status.name,
      sourceName: source?.displayName ?? source?.name,
      trackers: {
        for (final r in trackRecords.nodes)
          if (trackerNames[r.trackerId] case final name?) name.toLowerCase(),
      },
    );
  }
}

@freezed
abstract class MangaMeta with _$MangaMeta {
  factory MangaMeta({
    @JsonKey(
      name: "flutter_readerNavigationLayoutInvert",
      fromJson: MangaMeta.fromJsonToBool,
    )
    bool? invertTap,
    @JsonKey(name: "flutter_readerNavigationLayout")
    ReaderNavigationLayout? readerNavigationLayout,
    @JsonKey(name: "flutter_readerMode") ReaderMode? readerMode,
    @JsonKey(
      name: "flutter_readerPadding",
      fromJson: MangaMeta.fromJsonToDouble,
    )
    double? readerPadding,
    @JsonKey(name: "flutter_readerOrientation")
    ReaderOrientation? readerOrientation,
    @JsonKey(name: "flutter_readerTapInvert") TapInvert? readerTapInvert,
    @JsonKey(name: "flutter_scanlator") String? scanlator,
    @JsonKey(name: "flutter_rating", fromJson: MangaMeta.fromJsonToInt)
    int? rating,
    @JsonKey(name: "flutter_tags", fromJson: MangaMeta.fromJsonToStringList)
    List<String>? userTags,
    @JsonKey(
      name: "flutter_preferredScanlators",
      fromJson: MangaMeta.fromJsonToStringList,
    )
    List<String>? preferredScanlators,
    // This Tsumiru-only sort flag is separate from webUI_sortBy/webUI_reverse.
    @JsonKey(
      name: "flutter_chapterSortIsAlphabetical",
      fromJson: MangaMeta.fromJsonToBool,
    )
    bool? chapterSortAlphabetical,
  }) = _MangaMeta;

  static bool? fromJsonToBool(dynamic val) => val != null && val is String
      ? val.toLowerCase().compareTo(true.toString()) == 0
      : null;

  static double? fromJsonToDouble(dynamic val) =>
      val != null && val is String ? double.parse(val) : null;

  static int? fromJsonToInt(dynamic val) =>
      val is String ? int.tryParse(val) : null;

  /// User tags are JSON arrays in string-valued meta; invalid values decode to null.
  static List<String>? fromJsonToStringList(dynamic val) {
    if (val is! String || val.isEmpty) return null;
    try {
      final decoded = jsonDecode(val);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : null;
    } catch (_) {
      return null;
    }
  }

  factory MangaMeta.fromJson(Map<String, dynamic> json) =>
      _$MangaMetaFromJson(json);
}

extension MangaMetaPreferences on MangaMeta {
  List<String> get effectivePreferredScanlators {
    final stored = preferredScanlators;
    if (stored != null) return stored;
    final legacy = scanlator;
    // The legacy key's own name doubles as its "no filter" sentinel value.
    if (legacy == null || legacy == MangaMetaKeys.scanlator.key) {
      return const [];
    }
    return [legacy];
  }
}

extension MangaBaseExtensions on MangaBaseDto {
  String get displayCoverUrl => resolveDisplayCover(
    thumbnailUrl: thumbnailUrl,
    meta: meta.map((m) => (key: m.key, value: m.value)),
  );

  String? get coverVersion =>
      displayCoverUrl == thumbnailUrl ? thumbnailUrlLastFetched : null;
}

/// Cover to draw: the custom link when set, else the server cover.
String resolveDisplayCover({
  required String? thumbnailUrl,
  required Iterable<({String key, String value})> meta,
}) {
  for (final entry in meta) {
    if (entry.key == MangaMetaKeys.customCover.key) {
      final custom = entry.value.trim();
      if (custom.isNotEmpty) return custom;
      break;
    }
  }
  return thumbnailUrl ?? '';
}

enum MangaMetaKeys {
  customCover("tsumiru_customCover"),
  invertTap("flutter_readerNavigationLayoutInvert"),
  readerNavigationLayout("flutter_readerNavigationLayout"),
  readerMode("flutter_readerMode"),
  readerPadding("flutter_readerPadding"),
  readerOrientation("flutter_readerOrientation"),
  readerTapInvert("flutter_readerTapInvert"),
  scanlator("flutter_scanlator"),
  rating("flutter_rating"),
  tags("flutter_tags"),
  preferredScanlators("flutter_preferredScanlators"),
  // Keep this Tsumiru-only flag separate from the WebUI sort keys.
  chapterSortAlphabetical("flutter_chapterSortIsAlphabetical");

  const MangaMetaKeys(this.key);
  final String key;
}
