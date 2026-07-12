// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Derives the reader type from the series type (mangaType + defaultReaderType).
// Keep the lists and precedence verbatim — parity source, don't "improve".

import '../../../../../constants/enum.dart';

enum _MangaType { manga, manhwa, manhua, comic, webtoon }

/// The reader mode a Default-mode series should open in, from its type — or
/// null when the type carries no reliable signal (fall through to the user's
/// global default).
///
/// - webtoon / manhwa / manhua → continuous webtoon (Komikku parity).
/// - manga → single-page right-to-left, but **only on a positive `manga` tag**.
///   `_MangaType.manga` is also the classifier's fallback for untagged /
///   unrecognised series, and most modern manhwa land there — e.g. Asura Scans,
///   whose source isn't in Komikku's lists and whose entries carry only content
///   genres (Action/Fantasy/…). Mapping the whole bucket to RTL flipped every
///   such webtoon to right-to-left (and fit-to-screen zoomed the tall pages
///   out). So we trust only an explicit manga tag; the untagged fallback stays
///   null → the user's default (Komikku likewise leaves this bucket at default).
/// - comic → null (western comics vary; fall through to the default).
ReaderMode? autoReaderModeFor({
  required List<String>? genres,
  String? sourceName,
}) {
  final tags = genres ?? const [];
  return switch (_mangaType(tags, sourceName)) {
    _MangaType.webtoon ||
    _MangaType.manhwa ||
    _MangaType.manhua =>
      ReaderMode.webtoon,
    _MangaType.manga =>
      tags.any(_isMangaTag) ? ReaderMode.singleHorizontalRTL : null,
    _MangaType.comic => null,
  };
}

// Precedence: manga tag wins outright; then webtoon, comic, manhua, manhwa
// (tag or source name); fallback manga.
_MangaType _mangaType(List<String> tags, String? sourceName) {
  bool source(bool Function(String) predicate) =>
      sourceName != null && predicate(sourceName);

  if (tags.any(_isMangaTag)) return _MangaType.manga;
  if (tags.any(_isWebtoonTag) || source(_isWebtoonSource)) {
    return _MangaType.webtoon;
  }
  if (tags.any(_isComicTag) || source(_isComicSource)) {
    return _MangaType.comic;
  }
  if (tags.any(_isManhuaTag) || source(_isManhuaSource)) {
    return _MangaType.manhua;
  }
  if (tags.any(_isManhwaTag) || source(_isManhwaSource)) {
    return _MangaType.manhwa;
  }
  return _MangaType.manga;
}

// Kotlin's contains(other, ignoreCase = true).
bool _containsAny(String value, List<String> needles) {
  final lower = value.toLowerCase();
  return needles.any(lower.contains);
}

bool _isMangaTag(String tag) => _containsAny(tag, const ['manga', 'манга']);

bool _isManhuaTag(String tag) => _containsAny(tag, const ['manhua', 'маньхуа']);

bool _isManhwaTag(String tag) => _containsAny(tag, const ['manhwa', 'манхва']);

bool _isComicTag(String tag) => _containsAny(tag, const ['comic', 'комикс']);

bool _isWebtoonTag(String tag) =>
    _containsAny(tag, const ['long strip', 'webtoon']);

bool _isManhwaSource(String sourceName) => _containsAny(sourceName, const [
      'hiperdex',
      'hmanhwa',
      'instamanhwa',
      'manhwa18',
      'manhwa68',
      'manhwa365',
      'manhwahentaime',
      'manhwamanga',
      'manhwatop',
      'manhwa club',
      'manytoon',
      'manwha',
      'readmanhwa',
      'skymanga',
      'toonily',
      'webtoonxyz',
    ]);

bool _isWebtoonSource(String sourceName) => _containsAny(sourceName, const [
      'mangatoon',
      'manmanga',
      // 'tapas' commented out upstream too
      'toomics',
      'webcomics',
      'webtoons',
      'webtoon',
      // Beyond Komikku's list: modern scanlators that are always long-strip
      // and don't tag their entries by type.
      'asura',
    ]);

bool _isComicSource(String sourceName) => _containsAny(sourceName, const [
      '8muses',
      'allporncomic',
      'ciayo comics',
      'comicextra',
      'comicpunch',
      'cyanide',
      'dilbert',
      'eggporncomics',
      'existential comics',
      'hiveworks comics',
      'milftoon',
      'myhentaicomics',
      'myhentaigallery',
      'gunnerkrigg',
      'oglaf',
      'patch friday',
      'porncomix',
      'questionable content',
      'readcomiconline',
      'read comics online',
      'swords comic',
      'teabeer comics',
      'xkcd',
    ]);

bool _isManhuaSource(String sourceName) => _containsAny(sourceName, const [
      '1st kiss manhua',
      'hero manhua',
      'manhuabox',
      'manhuaus',
      'manhuas world',
      'manhuas.net',
      'readmanhua',
      'wuxiaworld',
      'manhua',
    ]);
