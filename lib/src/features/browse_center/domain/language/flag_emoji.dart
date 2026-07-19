// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Direct port of Komikku's tachiyomi-presentation-core FlagEmoji so the
// Sources filter screen shows the same per-language flags. Maps a source
// language code to a country, then to the two regional-indicator symbols that
// render as a flag emoji. Falls back to the globe (🌎) for unknown languages.

/// Regional indicators run from U+1F1E6 (A) to U+1F1FF (Z).
String _regionalIndicator(String char) {
  final upper = char.toUpperCase().codeUnitAt(0);
  return String.fromCharCode(0x1F1E6 + (upper - 0x41));
}

String _countryToFlag(String countryCode) {
  final code = countryCode.toUpperCase();
  return _regionalIndicator(code[0]) + _regionalIndicator(code[1]);
}

/// Language code -> country code. Keys and lookups are lower-cased so Tsumiru's
/// lower-case source langs (`pt-br`, `zh-hans`) match Komikku's cased entries.
const Map<String, String> _lang2Country = {
  'all': 'un',
  'af': 'za',
  'am': 'et',
  'ar': 'eg',
  'az': 'az',
  'be': 'by',
  'bg': 'bg',
  'bn': 'bd',
  'br': 'fr',
  'bs': 'ba',
  'ca': 'es',
  'ceb': 'ph',
  'cn': 'cn',
  'co': 'es',
  'cs': 'cz',
  'da': 'dk',
  'de': 'de',
  'el': 'gr',
  'en': 'us',
  'es-419': 'mx',
  'es': 'es',
  'et': 'ee',
  'eu': 'es',
  'fa': 'ir',
  'fi': 'fi',
  'fil': 'ph',
  'fo': 'fo',
  'fr': 'fr',
  'ga': 'ie',
  'gn': 'py',
  'gu': 'in',
  'ha': 'ng',
  'he': 'il',
  'hi': 'in',
  'hr': 'hr',
  'ht': 'ht',
  'hu': 'hu',
  'hy': 'am',
  'id': 'id',
  'ig': 'ng',
  'is': 'is',
  'it': 'it',
  'ja': 'jp',
  'jv': 'id',
  'ka': 'ge',
  'kk': 'kz',
  'km': 'kh',
  'kn': 'in',
  'ko': 'kr',
  'kr': 'ng',
  'ku': 'iq',
  'ky': 'kg',
  'lb': 'lu',
  'lmo': 'it',
  'lo': 'la',
  'lt': 'lt',
  'lv': 'lv',
  'mg': 'mg',
  'mi': 'nz',
  'mk': 'mk',
  'ml': 'in',
  'mn': 'mn',
  'mo': 'md',
  'mr': 'in',
  'ms': 'my',
  'mt': 'mt',
  'my': 'mm',
  'ne': 'np',
  'nl': 'nl',
  'no': 'no',
  'ny': 'mw',
  'pl': 'pl',
  'ps': 'af',
  'pt-br': 'br',
  'pt-pt': 'pt',
  'pt': 'pt',
  'rm': 'ch',
  'ro': 'ro',
  'ru': 'ru',
  'sd': 'pk',
  'sh': 'hr',
  'si': 'lk',
  'sk': 'sk',
  'sl': 'si',
  'sm': 'ws',
  'sn': 'zw',
  'so': 'so',
  'sq': 'al',
  'sr': 'hr',
  'st': 'ls',
  'sv': 'se',
  'sw': 'tz',
  'ta': 'in',
  'te': 'in',
  'tg': 'tj',
  'th': 'th',
  'ti': 'er',
  'tk': 'tm',
  'tl': 'ph',
  'to': 'to',
  'tr': 'tr',
  'uk': 'ua',
  'ur': 'pk',
  'uz': 'uz',
  'vec': 'it',
  'vi': 'vn',
  'yo': 'ng',
  'zh-hans': 'cn',
  'zh-hant': 'tw',
  'zh': 'cn',
  'zu': 'za',
  'gl': 'es',
  'in': 'id',
  'nb-no': 'no',
  'nn': 'no',
  'sc': 'it',
  'sdh': 'ir',
  'sah': 'ru',
  'cv': 'ru',
  'sa': 'in',
  'ka-ge': 'ge',
  'zh-cn': 'cn',
  'zh-tw': 'tw',
};

/// The flag emoji for a source language code (🌎 when unknown).
String flagEmojiForLang(String lang) {
  final country = _lang2Country[lang.toLowerCase()];
  return country != null ? _countryToFlag(country) : '\u{1F30E}';
}
