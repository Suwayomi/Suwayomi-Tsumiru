// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/content_rating.dart';

void main() {
  test('adult tags match whole tags case-insensitively, no false positives', () {
    expect(hasAdultTag(['Adult']), true);
    expect(hasAdultTag(['Ecchi', 'SMUT']), true);
    expect(hasAdultTag([' 18+ ']), true);

    // "Mature" marks dark themes on aggregators, not adult content — it was
    // flagging ordinary action manhwa. And whole-tag matching keeps compound
    // tags like "Young Adult" from tripping "adult".
    expect(hasAdultTag(['Mature']), false);
    expect(hasAdultTag(['Young Adult']), false);
    expect(hasAdultTag(['Action', 'Romance', 'Drama']), false);
    expect(hasAdultTag(const []), false);
  });
}
