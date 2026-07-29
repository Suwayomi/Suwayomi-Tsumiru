// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../graphql/__generated__/schema.graphql.dart';

/// Explicit allowlist, not `!= SAFE`: a future rating value must fail toward
/// hiding, never toward showing adult content to someone who opted out.
bool isNsfwFromWarning(Enum$ContentWarning warning) => switch (warning) {
      Enum$ContentWarning.SAFE => false,
      Enum$ContentWarning.MIXED || Enum$ContentWarning.NSFW => true,
      _ => true,
    };

/// Komikku's adult-tag vocabulary, ported verbatim from LewdMangaChecker.kt.
/// Matched as case-insensitive substrings, so "Mature" and "18+ content" hit.
const _adultTags = [
  'hentai',
  'adult',
  'smut',
  'lewd',
  'nsfw',
  'erotica',
  'pornographic',
  'mature',
  '18+',
];

bool hasAdultTag(Iterable<String> genre) {
  for (final tag in genre) {
    final lower = tag.toLowerCase();
    for (final adult in _adultTags) {
      if (lower.contains(adult)) return true;
    }
  }
  return false;
}

/// Whether one series counts as adult, for the library's content filter.
///
/// The server rates the *source*, but plenty of general sources carry R18
/// titles alongside everything else — which is what MIXED means. So MIXED
/// defers to the series' own tags, the way Komikku's isLewd() does; rating it
/// off the source alone would either hide every clean series on a mixed source
/// or leave the adult ones showing.
///
/// A MIXED source with no tags to test resolves to *not* adult, matching
/// Komikku (`genre.orEmpty().any { ... }` is false on an empty list). So an
/// uninitialised series on a mixed source shows until its metadata arrives.
/// That is the reference's behaviour, not an oversight — but it is the reason
/// an unfetched library is not a safe place to judge this filter.
bool isAdultManga(Enum$ContentWarning? warning, Iterable<String> genre) =>
    switch (warning) {
      Enum$ContentWarning.SAFE => false,
      Enum$ContentWarning.MIXED => hasAdultTag(genre),
      Enum$ContentWarning.NSFW => true,
      // No source (offline stub, or a manga the server could not attribute):
      // the tags are all we have.
      null => hasAdultTag(genre),
      _ => true,
    };
