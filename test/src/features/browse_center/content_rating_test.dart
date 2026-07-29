// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/content_rating.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

void main() {
  group('source-list policy', () {
    test('only SAFE is not adult', () {
      expect(isNsfwFromWarning(Enum$ContentWarning.SAFE), false);
      expect(isNsfwFromWarning(Enum$ContentWarning.MIXED), true);
      expect(isNsfwFromWarning(Enum$ContentWarning.NSFW), true);
    });
  });

  group('adult tags', () {
    test('matches as a case-insensitive substring', () {
      expect(hasAdultTag(['Mature']), true);
      expect(hasAdultTag(['18+ content']), true);
      expect(hasAdultTag(['Ecchi', 'SMUT']), true);
    });

    test('does not match ordinary tags', () {
      expect(hasAdultTag(['Action', 'Romance', 'Drama']), false);
      expect(hasAdultTag(const []), false);
    });
  });

  group('library filter: the series decides, not the source', () {
    // A MIXED source carries R18 titles alongside everything else. Rating the
    // whole source either hides every clean series on it or leaves the adult
    // ones showing — Komikku resolves it on the manga's own tags
    // (LewdMangaChecker.kt:19).
    test('MIXED source: a tagged series is adult', () {
      expect(isAdultManga(Enum$ContentWarning.MIXED, ['Adult']), true);
    });

    test('MIXED source: an untagged series is not', () {
      expect(isAdultManga(Enum$ContentWarning.MIXED, ['Action']), false);
    });

    test('NSFW source is adult regardless of tags', () {
      expect(isAdultManga(Enum$ContentWarning.NSFW, ['Action']), true);
    });

    test('SAFE source is not adult even if tags say otherwise', () {
      expect(isAdultManga(Enum$ContentWarning.SAFE, ['Hentai']), false);
    });

    test('no source falls back to the tags alone', () {
      expect(isAdultManga(null, ['Smut']), true);
      expect(isAdultManga(null, ['Action']), false);
    });
  });
}
