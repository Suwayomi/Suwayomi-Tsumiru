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
    test('matches whole tags case-insensitively', () {
      expect(hasAdultTag(['Adult']), true);
      expect(hasAdultTag(['Ecchi', 'SMUT']), true);
      expect(hasAdultTag([' 18+ ']), true);
    });

    // "Mature" marks dark themes on aggregators, not adult content — it was
    // flagging ordinary action manhwa. And whole-tag matching keeps compound
    // tags like "Young Adult" from tripping "adult".
    test('does not match Mature, compound tags, or ordinary tags', () {
      expect(hasAdultTag(['Mature']), false);
      expect(hasAdultTag(['Young Adult']), false);
      expect(hasAdultTag(['Action', 'Romance', 'Drama']), false);
      expect(hasAdultTag(const []), false);
    });
  });

  group('library filter: the series decides, not the source', () {
    // A MIXED source mixes R18 with clean titles; Komikku resolves it on the
    // manga's own tags, not the whole source (LewdMangaChecker.kt:19).
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

    // Komikku's `any {}` on an empty tag list is false, so an untagged series
    // on a mixed source shows — that's parity, not a leak.
    test('MIXED source with no tags yet is not adult', () {
      expect(isAdultManga(Enum$ContentWarning.MIXED, const []), false);
    });
  });
}
