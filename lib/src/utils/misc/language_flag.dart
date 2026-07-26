// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// ISO-639 language code → flag emoji, for the library's language badge.
///
/// System emoji rather than bundled drawables, so the badge is crisp at any
/// density with no assets. Codes with a region (`pt-BR`, `zh-Hant`) are matched
/// whole first, then by their base language.
library;

/// Suwayomi's local source reports this instead of a real language code.
const String kLocalSourceLang = 'localsourcelang';

/// Region overrides for codes whose flag differs from their base language.
/// Keys are lower-cased and `-`-separated.
const Map<String, String> _regionCountries = {
  'pt-br': 'BR',
  'pt-pt': 'PT',
  'zh-hans': 'CN',
  'zh-hant': 'TW',
  'zh-cn': 'CN',
  'zh-tw': 'TW',
  'zh-hk': 'HK',
  'es-419': 'MX',
  'es-mx': 'MX',
  'es-es': 'ES',
  'en-us': 'US',
  'en-gb': 'GB',
  'en-au': 'AU',
  'en-ca': 'CA',
  'en-in': 'IN',
  'fr-ca': 'CA',
  'nb-no': 'NO',
  'sr-latn': 'RS',
};

/// Base language → country whose flag stands in for it. Codes with no country
/// are omitted.
const Map<String, String> _languageCountries = {
  'af': 'ZA',
  'am': 'ET',
  'ar': 'SA',
  'az': 'AZ',
  'be': 'BY',
  'bg': 'BG',
  'bn': 'BD',
  'bs': 'BA',
  'ca': 'ES',
  'ceb': 'PH',
  'cs': 'CZ',
  'cv': 'RU',
  'da': 'DK',
  'de': 'DE',
  'el': 'GR',
  'en': 'US',
  'es': 'ES',
  'et': 'EE',
  'eu': 'ES',
  'fa': 'IR',
  'fi': 'FI',
  'fil': 'PH',
  'fo': 'FO',
  'fr': 'FR',
  'ga': 'IE',
  'gl': 'ES',
  'he': 'IL',
  'hi': 'IN',
  'hr': 'HR',
  'hu': 'HU',
  'hy': 'AM',
  'id': 'ID',
  'is': 'IS',
  'it': 'IT',
  'ja': 'JP',
  'jv': 'ID',
  'ka': 'GE',
  'kk': 'KZ',
  'km': 'KH',
  'kn': 'IN',
  'ko': 'KR',
  'ku': 'TR',
  'ky': 'KG',
  'lt': 'LT',
  'lv': 'LV',
  'mk': 'MK',
  'ml': 'IN',
  'mn': 'MN',
  'mr': 'IN',
  'ms': 'MY',
  'my': 'MM',
  'nb': 'NO',
  'ne': 'NP',
  'nl': 'NL',
  'nn': 'NO',
  'no': 'NO',
  'pl': 'PL',
  'ps': 'AF',
  'pt': 'PT',
  'ro': 'RO',
  'ru': 'RU',
  'sh': 'RS',
  'si': 'LK',
  'sk': 'SK',
  'sl': 'SI',
  'sq': 'AL',
  'sr': 'RS',
  'sv': 'SE',
  'sw': 'TZ',
  'ta': 'IN',
  'te': 'IN',
  'th': 'TH',
  'tl': 'PH',
  'tr': 'TR',
  'uk': 'UA',
  'ur': 'PK',
  'uz': 'UZ',
  'vi': 'VN',
  'zh': 'CN',
  'zu': 'ZA',
};

/// The flag emoji for [langCode], or null when the code maps to no flag — the
/// badge falls back to the uppercase code then. Accepts `es`, `pt-BR`,
/// `zh_Hant`, `PT-br` — anything the server reports as a source language.
String? languageFlagEmoji(String? langCode) {
  if (langCode == null || langCode.isEmpty) return null;
  final normalized = langCode.trim().toLowerCase().replaceAll('_', '-');
  // Suwayomi's "any language" meta values, plus constructed languages.
  if (const {'all', 'other', 'none', 'eo', 'la'}.contains(normalized)) {
    return null;
  }
  final country = _regionCountries[normalized] ??
      _languageCountries[normalized.split('-').first];
  return country == null ? null : _flagFromCountryCode(country);
}

/// English display names for the "By language" grouping labels. Neither Dart
/// nor `intl` exposes an ISO-639 name table, so this mirrors the
/// [_languageCountries] key set.
const Map<String, String> _languageNames = {
  'af': 'Afrikaans',
  'am': 'Amharic',
  'ar': 'Arabic',
  'az': 'Azerbaijani',
  'be': 'Belarusian',
  'bg': 'Bulgarian',
  'bn': 'Bengali',
  'bs': 'Bosnian',
  'ca': 'Catalan',
  'ceb': 'Cebuano',
  'cs': 'Czech',
  'cv': 'Chuvash',
  'da': 'Danish',
  'de': 'German',
  'el': 'Greek',
  'en': 'English',
  'eo': 'Esperanto',
  'es': 'Spanish',
  'et': 'Estonian',
  'eu': 'Basque',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fil': 'Filipino',
  'fo': 'Faroese',
  'fr': 'French',
  'ga': 'Irish',
  'gl': 'Galician',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hr': 'Croatian',
  'hu': 'Hungarian',
  'hy': 'Armenian',
  'id': 'Indonesian',
  'is': 'Icelandic',
  'it': 'Italian',
  'ja': 'Japanese',
  'jv': 'Javanese',
  'ka': 'Georgian',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'kn': 'Kannada',
  'ko': 'Korean',
  'ku': 'Kurdish',
  'ky': 'Kyrgyz',
  'la': 'Latin',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'mk': 'Macedonian',
  'ml': 'Malayalam',
  'mn': 'Mongolian',
  'mr': 'Marathi',
  'ms': 'Malay',
  'my': 'Burmese',
  'nb': 'Norwegian',
  'ne': 'Nepali',
  'nl': 'Dutch',
  'nn': 'Norwegian',
  'no': 'Norwegian',
  'pl': 'Polish',
  'ps': 'Pashto',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sh': 'Serbo-Croatian',
  'si': 'Sinhala',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'sq': 'Albanian',
  'sr': 'Serbian',
  'sv': 'Swedish',
  'sw': 'Swahili',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tl': 'Tagalog',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'zh': 'Chinese',
  'zu': 'Zulu',
};

/// The region suffix worth keeping in a display name, so `pt-BR` reads
/// "Portuguese (BR)". Script subtags (Hans/Hant) and numeric UN M.49 codes read
/// fine uppercased as-is; anything longer is noise.
String? _regionSuffix(String normalized) {
  final parts = normalized.split('-');
  if (parts.length < 2) return null;
  final region = parts.last;
  return region.length <= 4 ? region.toUpperCase() : null;
}

/// A human label for [langCode] — "Japanese", "Portuguese (BR)", or the
/// uppercase code when unmapped.
String languageDisplayName(String? langCode) {
  if (langCode == null || langCode.isEmpty) return '';
  final normalized = langCode.trim().toLowerCase().replaceAll('_', '-');
  final base = normalized.split('-').first;
  final name = _languageNames[base];
  if (name == null) return normalized.toUpperCase();
  final region = _regionSuffix(normalized);
  return region == null ? name : '$name ($region)';
}

/// Maps each letter of a 2-letter country code to its Unicode
/// regional-indicator symbol (U+1F1E6 = 'A').
String _flagFromCountryCode(String countryCode) {
  const base = 0x1F1E6;
  const letterA = 0x41; // 'A'
  final upper = countryCode.toUpperCase();
  return String.fromCharCodes([
    base + (upper.codeUnitAt(0) - letterA),
    base + (upper.codeUnitAt(1) - letterA),
  ]);
}
