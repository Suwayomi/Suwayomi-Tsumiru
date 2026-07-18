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
/// null when the type carries no opinion (fall through to the user's default).
///
/// Verbatim parity with Komikku's `defaultReaderType`: auto-detect only ever
/// rescues long-strip content to the webtoon viewer (reading a tall strip as
/// fixed pages is broken, not a taste call). It never picks a page *direction*
/// — LTR vs RTL is pure preference and stays with the user's default.
///
/// - webtoon / manhwa / manhua → continuous webtoon.
/// - manga / comic → null → the user's global (or per-series) default. Manga
///   opens right-to-left by shipping RTL as the factory default, not by a
///   detection rule that would override anyone who set LTR.
ReaderMode? autoReaderModeFor({
  required List<String>? genres,
  String? sourceName,
}) {
  return switch (_mangaType(genres ?? const [], sourceName)) {
    _MangaType.webtoon ||
    _MangaType.manhwa ||
    _MangaType.manhua =>
      ReaderMode.webtoon,
    _MangaType.manga || _MangaType.comic => null,
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
