// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Chip adapter (§2.5): chips are a lossless view over the stored 8-value
// ReaderMode; the two continuous-horizontal orphans never get a lying chip.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_mode_adapter.dart';

const orphans = {
  ReaderMode.continuousHorizontalLTR,
  ReaderMode.continuousHorizontalRTL,
};

void main() {
  group('ReaderModeAdapter', () {
    test('locked chip↔mode mapping', () {
      expect(ReaderModeAdapter.toChip(ReaderMode.defaultReader),
          ReadingModeChip.defaultChip);
      expect(ReaderModeAdapter.toChip(ReaderMode.singleHorizontalLTR),
          ReadingModeChip.pagedLTR);
      expect(ReaderModeAdapter.toChip(ReaderMode.singleHorizontalRTL),
          ReadingModeChip.pagedRTL);
      expect(ReaderModeAdapter.toChip(ReaderMode.singleVertical),
          ReadingModeChip.pagedVertical);
      expect(ReaderModeAdapter.toChip(ReaderMode.webtoon),
          ReadingModeChip.longStrip);
      expect(ReaderModeAdapter.toChip(ReaderMode.continuousVertical),
          ReadingModeChip.longStripGaps);
    });

    test('fromChip(toChip(x)) == x for every mapped mode', () {
      for (final mode in ReaderMode.values.where((m) => !orphans.contains(m))) {
        final chip = ReaderModeAdapter.toChip(mode);
        expect(chip, isNotNull, reason: '$mode must have a parity chip');
        expect(ReaderModeAdapter.fromChip(chip!), mode);
      }
    });

    test('toChip(fromChip(chip)) == chip for every chip', () {
      for (final chip in ReadingModeChip.values) {
        expect(ReaderModeAdapter.toChip(ReaderModeAdapter.fromChip(chip)),
            chip);
      }
    });

    test('orphans have no parity chip and are flagged legacy', () {
      for (final orphan in orphans) {
        expect(ReaderModeAdapter.toChip(orphan), isNull);
        expect(ReaderModeAdapter.isLegacyOrphan(orphan), isTrue);
      }
      for (final mode in ReaderMode.values.where((m) => !orphans.contains(m))) {
        expect(ReaderModeAdapter.isLegacyOrphan(mode), isFalse);
      }
    });

    test('fromChip never emits an orphan', () {
      for (final chip in ReadingModeChip.values) {
        expect(orphans, isNot(contains(ReaderModeAdapter.fromChip(chip))));
      }
    });
  });
}
