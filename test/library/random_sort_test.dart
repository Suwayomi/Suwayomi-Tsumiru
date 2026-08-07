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

    test('is non-negative (masked to 0x7fffffff)', () {
      for (final id in [0, 1, 100, 99999, -1, -42]) {
        expect(randomKey(id, 0), greaterThanOrEqualTo(0));
        expect(randomKey(id, 12345), greaterThanOrEqualTo(0));
      }
    });

    test('different seeds produce a different ordering for a fixed id list', () {
      final ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

      List<int> sortedWith(int seed) =>
          [...ids]..sort((a, b) => randomKey(a, seed).compareTo(randomKey(b, seed)));

      final order0 = sortedWith(0);
      final order1 = sortedWith(1);

      // The two orderings must differ (with overwhelmingly high probability for
      // the Knuth-multiplicative hash used; the ids 1..10 are known to differ).
      expect(order0, isNot(equals(order1)),
          reason: 'seed 0 and seed 1 should produce different orderings');
    });

    test('same seed reproduces the same ordering', () {
      final ids = [10, 20, 30, 40, 50];

      List<int> sortedWith(int seed) =>
          [...ids]..sort((a, b) => randomKey(a, seed).compareTo(randomKey(b, seed)));

      expect(sortedWith(7), equals(sortedWith(7)));
      expect(sortedWith(42), equals(sortedWith(42)));
    });
  });
}
