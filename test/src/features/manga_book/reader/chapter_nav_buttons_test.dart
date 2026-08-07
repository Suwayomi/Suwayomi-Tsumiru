// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/chapter_nav_buttons.dart';

void main() {
  group('chapterNavCallbacks', () {
    void previous() {}
    void next() {}

    test('LTR: leading button goes back, trailing goes forward', () {
      final mapped = chapterNavCallbacks(
        isRtl: false,
        onPreviousChapter: previous,
        onNextChapter: next,
      );

      expect(mapped.leading, same(previous));
      expect(mapped.trailing, same(next));
    });

    test('RTL: leading button goes forward, trailing goes back', () {
      final mapped = chapterNavCallbacks(
        isRtl: true,
        onPreviousChapter: previous,
        onNextChapter: next,
      );

      expect(mapped.leading, same(next),
          reason: 'in RTL the left-pointing arrow advances the story');
      expect(mapped.trailing, same(previous));
    });

    test('a missing chapter stays missing through the RTL swap', () {
      final mapped = chapterNavCallbacks(
        isRtl: true,
        onPreviousChapter: previous,
        onNextChapter: null,
      );

      expect(mapped.leading, isNull,
          reason: 'no next chapter must disable whichever button targets it');
      expect(mapped.trailing, same(previous));
    });
  });
}
