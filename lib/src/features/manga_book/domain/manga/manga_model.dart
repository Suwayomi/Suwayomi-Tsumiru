// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../constants/enum.dart';
import '../../../../features/library/domain/library_search_query.dart';
import 'graphql/__generated__/fragment.graphql.dart';

part 'manga_model.freezed.dart';
part 'manga_model.g.dart';

typedef MangaDto = Fragment$MangaDto;

typedef MangaBaseDto = Fragment$MangaBaseDto;

extension MangaExtensions on MangaDto {
  MangaMeta get metaData => MangaMeta.fromJson(
      {for (final metaItem in meta) metaItem.key: metaItem.value});

  /// Whether this manga matches [query] under the library search DSL. Used by
  /// quick-search; the library list parses the query once instead (see
  /// applyLibraryFilterSort).
  bool query([String? query]) =>
      LibrarySearchQuery.parse(query).matches(filterFields());

  /// Flattened field view used by the library search DSL (see
  /// [LibrarySearchQuery]). Resolves meta once so rating/tags come from the same
  /// build as the rest of the fields. [trackerNames] maps tracker id → service
  /// name so the `tracked:<service>` metatag can resolve; pass it empty (the
  /// default) when only the bool `tracked:` form is needed.
  LibraryFilterFields filterFields([Map<int, String> trackerNames = const {}]) {
    final m = metaData;
    return LibraryFilterFields(
      title: title,
      author: author,
      artist: artist,
      genres: genre.toList(),
      unreadCount: unreadCount,
      downloadCount: downloadCount,
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
    @JsonKey(
      name: "flutter_readerMagnifierSize",
      fromJson: MangaMeta.fromJsonToDouble,
    )
    double? readerMagnifierSize,
    @JsonKey(name: "flutter_readerOrientation")
    ReaderOrientation? readerOrientation,
    @JsonKey(name: "flutter_readerTapInvert") TapInvert? readerTapInvert,
    @JsonKey(name: "flutter_scanlator") String? scanlator,
    @JsonKey(name: "flutter_chapterListMode") ChapterListMode? chapterListMode,
    @JsonKey(name: "flutter_rating", fromJson: MangaMeta.fromJsonToInt)
    int? rating,
    @JsonKey(name: "flutter_tags", fromJson: MangaMeta.fromJsonToStringList)
    List<String>? userTags,
    @JsonKey(
      name: "flutter_preferredScanlators",
      fromJson: MangaMeta.fromJsonToStringList,
    )
    List<String>? preferredScanlators,
  }) = _MangaMeta;

  static bool? fromJsonToBool(dynamic val) => val != null && val is String
      ? val.toLowerCase().compareTo(true.toString()) == 0
      : null;

  static double? fromJsonToDouble(dynamic val) =>
      val != null && val is String ? double.parse(val) : null;

  static int? fromJsonToInt(dynamic val) =>
      val is String ? int.tryParse(val) : null;

  /// User tags are stored as a JSON string array in the (String-typed) meta
  /// store. Bad/legacy values decode to null rather than throwing.
  static List<String>? fromJsonToStringList(dynamic val) {
    if (val is! String || val.isEmpty) return null;
    try {
      final decoded = jsonDecode(val);
      return decoded is List
          ? decoded.map((e) => e.toString()).toList()
          : null;
    } catch (_) {
      return null;
    }
  }
  factory MangaMeta.fromJson(Map<String, dynamic> json) =>
      _$MangaMetaFromJson(json);
}

enum MangaMetaKeys {
  invertTap("flutter_readerNavigationLayoutInvert"),
  readerNavigationLayout("flutter_readerNavigationLayout"),
  readerMode("flutter_readerMode"),
  readerPadding("flutter_readerPadding"),
  readerMagnifierSize("flutter_readerMagnifierSize"),
  readerOrientation("flutter_readerOrientation"),
  readerTapInvert("flutter_readerTapInvert"),
  scanlator("flutter_scanlator"),
  chapterListMode("flutter_chapterListMode"),
  rating("flutter_rating"),
  tags("flutter_tags"),
  preferredScanlators("flutter_preferredScanlators"),
  ;

  const MangaMetaKeys(this.key);
  final String key;
}
