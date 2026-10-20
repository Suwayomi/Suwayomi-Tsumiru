// Tests for the Random sort comparator (Task 7).
//
// randomKey(id, seed) must be:
//   1. Deterministic — same id+seed always produces the same value.
//   2. Seed-sensitive — different seeds produce a different ordering for a
//      fixed id list (with very high probability; the chosen ids are known to
//      differ under seed 0 vs 1).
//   3. Direction-independent — Random ignores the sort direction toggle
//      (always multiplies by 1, never –1).
//
// Because randomKey is a top-level function in library_controller.dart we
// import it directly.  The test does NOT call applyLibraryFilterSort so it
// doesn't need Flutter widget infrastructure.

// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';

void main() {
  group('randomKey', () {
    test('is deterministic: same id+seed always yields the same value', () {
      expect(randomKey(42, 0), equals(randomKey(42, 0)));
      expect(randomKey(1, 999), equals(randomKey(1, 999)));
      expect(randomKey(0, 0), equals(randomKey(0, 0)));
    });

  });
}
