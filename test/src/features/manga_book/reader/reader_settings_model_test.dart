// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// ReaderSetting descriptors: pins the perSeries ?? global resolution.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_setting.dart';

void main() {
  group('ReaderSetting<T>.resolve', () {
    const setting = ReaderSetting<double>(
      scope: ReaderSettingScope.perSeries,
      perSeriesKey: MangaMetaKeys.readerPadding,
      fallback: 0.0,
    );

    test('per-series X beats global Y', () {
      expect(setting.resolve(0.3, 0.1), 0.3);
    });
  });
}
