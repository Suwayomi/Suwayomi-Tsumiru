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
    test('fromChip(toChip(x)) == x for every mapped mode', () {
      for (final mode in ReaderMode.values.where((m) => !orphans.contains(m))) {
        final chip = ReaderModeAdapter.toChip(mode);
        expect(chip, isNotNull, reason: '$mode must have a parity chip');
        expect(ReaderModeAdapter.fromChip(chip!), mode);
      }
    });
  });
}
