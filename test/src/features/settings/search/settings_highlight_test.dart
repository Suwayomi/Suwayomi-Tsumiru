// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/search/settings_highlight_target.dart';

bool _isHighlight(DecoratedBox box) {
  final decoration = box.decoration;
  if (decoration is! BoxDecoration) return false;
  final tint = decoration.color;
  if (tint != null && tint.a > 0) return true;
  final border = decoration.border;
  if (border is Border && border.left.color.a > 0) return true;
  return false;
}

Finder _highlightOf(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is DecoratedBox && _isHighlight(w)),
);

/// The highlight wrapper around [label] while its tint is up, or null when
/// the tint is off (including the pre-pulse pause, when only the bar shows).
BoxDecoration? _tintedDecoration(WidgetTester tester, String label) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0) {
      return decoration;
    }
  }
  return null;
}

Color _primaryOf(WidgetTester tester, String label) =>
    Theme.of(tester.element(find.text(label))).colorScheme.primary;

// Without a scope the target scrolls itself into view once mounted, so it
// must start built but off-screen: item 13 sits below the 600 px test
// viewport yet inside the default 250 px cache extent. Farther items never
// mount until the list scrolls near them — the scoped test below covers that.
Future<void> _pumpTarget(
  WidgetTester tester,
  String activeId, {
  bool reduceMotion = false,
  int items = 20,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < items; i++)
                SettingsHighlightTarget(
                  id: 'item$i',
                  activeId: activeId,
                  child: ListTile(title: Text('Setting $i')),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

// Row 75 of 80 in the 600 px test viewport: never mounted until the scope's
// seeker steps the list toward it. Driven through the scope (no activeId),
// like the real screens driven by the route query.
Future<void> _pumpLongList(WidgetTester tester, String highlightId) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsHighlightScope(
          highlightId: highlightId,
          child: ListView.builder(
            itemCount: 80,
            itemBuilder: (context, i) => SettingsHighlightTarget(
              id: 'item$i',
              child: ListTile(title: Text('Setting $i')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SettingsHighlightTarget', () {
    testWidgets('matching target scrolls into view and pulses', (tester) async {
      await _pumpTarget(tester, 'item13');
      expect(find.text('Setting 13'), findsNothing);

      // First frame arms the target; the 300 ms scroll centres it.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Setting 13'), findsOneWidget);

      // 600 ms pause, then the pulse starts: tint visible mid-first-pulse,
      // primary at up to 18%, with the 3 px bar solid at full opacity.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_highlightOf('Setting 13'), findsOneWidget);
      final decoration = _tintedDecoration(tester, 'Setting 13')!;
      final primary = _primaryOf(tester, 'Setting 13');
      expect(decoration.color!.r, moreOrLessEquals(primary.r));
      expect(decoration.color!.g, moreOrLessEquals(primary.g));
      expect(decoration.color!.b, moreOrLessEquals(primary.b));
      expect(decoration.color!.a, greaterThan(0));
      expect(decoration.color!.a, lessThanOrEqualTo(0.18));
      final bar = (decoration.border! as Border).left;
      expect(bar.width, 3);
      expect(bar.color.a, moreOrLessEquals(1, epsilon: 0.001));

      // Through the rest of the pulse (~2 s) the highlight is gone for good.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_highlightOf('Setting 13'), findsNothing);
      expect(find.text('Setting 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion shows a steady tint instead', (tester) async {
      await _pumpTarget(tester, 'item13', reduceMotion: true);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Setting 13'), findsOneWidget);

      // No 600 ms pause, no pulse: the steady tint is up at once and stays.
      expect(_highlightOf('Setting 13'), findsOneWidget);
      var decoration = _tintedDecoration(tester, 'Setting 13')!;
      expect(decoration.color!.a, moreOrLessEquals(0.18, epsilon: 0.001));
      await tester.pump(const Duration(seconds: 1));
      expect(_highlightOf('Setting 13'), findsOneWidget);
      decoration = _tintedDecoration(tester, 'Setting 13')!;
      expect(decoration.color!.a, moreOrLessEquals(0.18, epsilon: 0.001));

      // After ~2 s it fades out and stays off.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_highlightOf('Setting 13'), findsNothing);
      expect(find.text('Setting 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('far target is sought out, scrolled to, and pulsed', (
      tester,
    ) async {
      await _pumpLongList(tester, 'item75');
      expect(find.text('Setting 75'), findsNothing);

      // Row 75 starts unmounted; the seeker steps the list until it mounts.
      for (
        var i = 0;
        i < 60 && find.text('Setting 75').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Setting 75'), findsOneWidget);

      // After the 600 ms pause the pulse tint shows: the row was scrolled
      // properly into view (centred on screen, not just in cache) and the
      // bar is solid while the tint pulses.
      BoxDecoration? decoration;
      for (var i = 0; i < 60 && decoration == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        decoration = _tintedDecoration(tester, 'Setting 75');
      }
      expect(decoration, isNotNull);
      final primary = _primaryOf(tester, 'Setting 75');
      expect(decoration!.color!.r, moreOrLessEquals(primary.r));
      expect(decoration.color!.g, moreOrLessEquals(primary.g));
      expect(decoration.color!.b, moreOrLessEquals(primary.b));
      expect(decoration.color!.a, greaterThan(0));
      expect(decoration.color!.a, lessThanOrEqualTo(0.18));
      final bar = (decoration.border! as Border).left;
      expect(bar.width, 3);
      expect(bar.color.a, moreOrLessEquals(1, epsilon: 0.001));
      expect(
        tester.getCenter(find.text('Setting 75')).dy,
        inInclusiveRange(0, 600),
      );

      // The highlight finishes and stays off.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_highlightOf('Setting 75'), findsNothing);
      expect(find.text('Setting 75'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
