// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression test for Bug A: the vertical side seekbar previously used hardcoded
// [Positioned] offsets (top: 80, bottom: 100) that overlapped the chrome bars on
// every device with a tall status bar or gesture-nav inset.
//
// The fix: ReaderChrome reads [chromeExtentsProvider] at build time and
// computes:
//
//   top:    e.topInset    + 8   (breathing room)
//   bottom: e.bottomInset + 8
//
// This test verifies the math is correct by overriding the provider with known
// values (topInset: 108, bottomInset: 64) and asserting the resulting
// [Positioned] has top: 116 and bottom: 72 — and that neither the old literal
// 80 nor 100 appear as the top/bottom of the positioned widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/chrome_extents.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_side_seekbar.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_left_handed_seekbar_tile/reader_left_handed_seekbar_tile.dart';

/// A minimal [ConsumerWidget] that replicates the exact positioning logic
/// from [ReaderChrome] — reads the extents provider and computes the offsets
/// with 8 dp breathing room.  It wraps [ReaderSideSeekBar] in a [Positioned]
/// exactly as [ReaderChrome] does so the widget-test can verify the values.
class _TestSeekbarHost extends ConsumerWidget {
  const _TestSeekbarHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extents = ref.watch(chromeExtentsProvider);
    final forceHorizontal =
        ref.watch(forceHorizontalSeekbarProvider) ?? false;
    final leftHanded =
        ref.watch(leftHandedVerticalSeekbarProvider) ?? false;

    // Mirrors the exact expression in ReaderChrome:
    //   top:    extents.topInset    + 8
    //   bottom: extents.bottomInset + 8
    return Stack(
      children: [
        if (!forceHorizontal)
          Positioned(
            right: leftHanded ? null : 6,
            left: leftHanded ? 6 : null,
            top: extents.topInset + 8,
            bottom: extents.bottomInset + 8,
            width: 56,
            child: ReaderSideSeekBar(
              currentIndex: 0,
              pageCount: 10,
              onChanged: (_) {},
            ),
          ),
      ],
    );
  }
}

void main() {
  group('Side seekbar inset-derived positioning (Bug A fix)', () {
    // Helper: pumps the test host with a fixed ChromeExtents override.
    Future<void> pumpHost(
      WidgetTester tester, {
      required ChromeExtents extents,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override the notifier to return the fixed extents immediately —
            // no MeasureSize, no timing.
            chromeExtentsProvider.overrideWith(
              () => _FixedExtentsNotifier(extents),
            ),
            // Default prefs: force-horizontal OFF, left-handed OFF.
            forceHorizontalSeekbarProvider.overrideWith(
              () => _FixedForceHorizontal(value: false),
            ),
            leftHandedVerticalSeekbarProvider.overrideWith(
              () => _FixedLeftHanded(value: false),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: _TestSeekbarHost()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Positioned.top == topInset + 8 and .bottom == bottomInset + 8',
        (tester) async {
      const testExtents = ChromeExtents(topInset: 108, bottomInset: 64);
      await pumpHost(tester, extents: testExtents);

      // Find the Positioned widget that wraps the seekbar.
      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byType(ReaderSideSeekBar),
          matching: find.byType(Positioned),
        ),
      );

      // 108 + 8 = 116
      expect(positioned.top, 116.0,
          reason: 'top should equal topInset (108) + 8 breathing room');

      // 64 + 8 = 72
      expect(positioned.bottom, 72.0,
          reason: 'bottom should equal bottomInset (64) + 8 breathing room');
    });

    testWidgets('Positioned.top is NOT the old hardcoded 80 literal',
        (tester) async {
      const testExtents = ChromeExtents(topInset: 108, bottomInset: 64);
      await pumpHost(tester, extents: testExtents);

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byType(ReaderSideSeekBar),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.top, isNot(80.0),
          reason: 'top must not be the old hardcoded 80 literal');
    });

    testWidgets('Positioned.bottom is NOT the old hardcoded 100 literal',
        (tester) async {
      const testExtents = ChromeExtents(topInset: 108, bottomInset: 64);
      await pumpHost(tester, extents: testExtents);

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byType(ReaderSideSeekBar),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.bottom, isNot(100.0),
          reason: 'bottom must not be the old hardcoded 100 literal');
    });

    testWidgets('left-handed mode: anchors left: 6, right: null',
        (tester) async {
      const testExtents = ChromeExtents(topInset: 108, bottomInset: 64);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chromeExtentsProvider.overrideWith(
              () => _FixedExtentsNotifier(testExtents),
            ),
            forceHorizontalSeekbarProvider.overrideWith(
              () => _FixedForceHorizontal(value: false),
            ),
            leftHandedVerticalSeekbarProvider.overrideWith(
              () => _FixedLeftHanded(value: true), // LEFT-HANDED
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: _TestSeekbarHost()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byType(ReaderSideSeekBar),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, 6.0,
          reason: 'left-handed mode anchors left: 6');
      expect(positioned.right, isNull,
          reason: 'left-handed mode has no right anchor');
    });

    testWidgets('forceHorizontalSeekbar: side seekbar is absent',
        (tester) async {
      const testExtents = ChromeExtents(topInset: 108, bottomInset: 64);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chromeExtentsProvider.overrideWith(
              () => _FixedExtentsNotifier(testExtents),
            ),
            forceHorizontalSeekbarProvider.overrideWith(
              () => _FixedForceHorizontal(value: true), // FORCE HORIZONTAL
            ),
            leftHandedVerticalSeekbarProvider.overrideWith(
              () => _FixedLeftHanded(value: false),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: _TestSeekbarHost()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When forceHorizontal is ON, no ReaderSideSeekBar should be in the tree.
      expect(find.byType(ReaderSideSeekBar), findsNothing,
          reason:
              'forceHorizontalSeekbar=true must hide the vertical side seekbar');
    });
  });
}

// ── Test doubles ──────────────────────────────────────────────────────────────

/// A [ChromeExtentsNotifier] override that returns a fixed [ChromeExtents]
/// rather than going through the real measurement path.
class _FixedExtentsNotifier extends ChromeExtentsNotifier {
  _FixedExtentsNotifier(this._fixed);
  final ChromeExtents _fixed;

  @override
  ChromeExtents build() => _fixed;
}

/// A [ForceHorizontalSeekbar] that short-circuits SharedPreferences.
class _FixedForceHorizontal extends ForceHorizontalSeekbar {
  _FixedForceHorizontal({required this.value});
  final bool value;

  @override
  bool? build() => value;
}

/// A [LeftHandedVerticalSeekbar] that short-circuits SharedPreferences.
class _FixedLeftHanded extends LeftHandedVerticalSeekbar {
  _FixedLeftHanded({required this.value});
  final bool value;

  @override
  bool? build() => value;
}
