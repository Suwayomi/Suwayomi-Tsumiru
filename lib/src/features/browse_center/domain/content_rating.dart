// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../graphql/__generated__/schema.graphql.dart';

/// Unknown ratings fail closed when adult content is disabled.
bool isNsfwFromWarning(Enum$ContentWarning warning) => switch (warning) {
      Enum$ContentWarning.SAFE => false,
      Enum$ContentWarning.MIXED || Enum$ContentWarning.NSFW => true,
      _ => true,
    };

// Match whole tags; "mature" denotes dark themes and is not treated as adult content.
const _adultTags = {
  'hentai',
  'adult',
  'smut',
  'lewd',
  'nsfw',
  'erotica',
  'pornographic',
  '18+',
};

bool hasAdultTag(Iterable<String> genre) =>
    genre.any((tag) => _adultTags.contains(tag.trim().toLowerCase()));

/// MIXED or unknown sources use series tags; untagged series are treated as safe.
bool isAdultManga(Enum$ContentWarning? warning, Iterable<String> genre) =>
    switch (warning) {
      Enum$ContentWarning.SAFE => false,
      Enum$ContentWarning.MIXED => hasAdultTag(genre),
      Enum$ContentWarning.NSFW => true,
      null => hasAdultTag(genre),
      _ => true,
    };
