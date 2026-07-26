// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/misc/language_flag.dart';

void main() {
  group('languageFlagEmoji', () {
    test('maps plain ISO-639 codes', () {
      expect(languageFlagEmoji('es'), '🇪🇸');
      expect(languageFlagEmoji('en'), '🇺🇸');
      expect(languageFlagEmoji('ja'), '🇯🇵');
      expect(languageFlagEmoji('ko'), '🇰🇷');
      expect(languageFlagEmoji('zh'), '🇨🇳');
    });

    test('region variants win over the base language', () {
      expect(languageFlagEmoji('pt-BR'), '🇧🇷');
      expect(languageFlagEmoji('pt'), '🇵🇹');
      expect(languageFlagEmoji('zh-Hant'), '🇹🇼');
      expect(languageFlagEmoji('en-GB'), '🇬🇧');
    });

    test('normalizes case and underscore separators', () {
      expect(languageFlagEmoji('PT_br'), '🇧🇷');
      expect(languageFlagEmoji('  FR  '), '🇫🇷');
    });

    test('falls back to the base language for unknown regions', () {
      expect(languageFlagEmoji('de-AT'), '🇩🇪');
    });

    test('returns null when there is no sensible flag', () {
      expect(languageFlagEmoji(null), isNull);
      expect(languageFlagEmoji(''), isNull);
      // Suwayomi's "any language" sentinel and constructed languages.
      expect(languageFlagEmoji('all'), isNull);
      expect(languageFlagEmoji('eo'), isNull);
      // Unmapped code — the badge falls back to the uppercase text.
      expect(languageFlagEmoji('xx'), isNull);
    });
  });
}
