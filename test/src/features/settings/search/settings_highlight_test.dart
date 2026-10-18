// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/search/settings_highlight_target.dart';

Finder _tintOf(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate(
    (w) => w is Container && w.color != null && w.color!.a > 0,
  ),
);

// The target scrolls itself into view once mounted, so it must start built
// but off-screen: item 13 sits below the 600 px test viewport yet inside the
// default 250 px cache extent. Farther items never mount until the list
// scrolls near them, which no self-scroll can trigger.
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

void main() {
  group('SettingsHighlightTarget', () {
    testWidgets('non-matching id renders the child untouched', (tester) async {
      await _pumpTarget(tester, 'item7');

      expect(find.text('Setting 0'), findsOneWidget);
      expect(find.text('Setting 7'), findsOneWidget);
      expect(find.text('Setting 59'), findsNothing);
      // The tint wrapper only mounts for the active target mid-pulse;
      // nothing else in the tree paints a tinted container.
      expect(_tintOf('Setting 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('matching target scrolls into view and pulses', (tester) async {
      await _pumpTarget(tester, 'item13');
      expect(find.text('Setting 13'), findsNothing);

      // First frame arms the target; the 300 ms scroll centres it.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Setting 13'), findsOneWidget);

      // 600 ms pause, then the pulse starts: tint visible mid-first-pulse.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_tintOf('Setting 13'), findsOneWidget);

      // Through the rest of the pulse (~2 s) the tint is gone for good.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_tintOf('Setting 13'), findsNothing);
      expect(find.text('Setting 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion shows a steady tint instead', (tester) async {
      await _pumpTarget(tester, 'item13', reduceMotion: true);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Setting 13'), findsOneWidget);

      // No 600 ms pause, no pulse: the steady tint is up at once and stays.
      expect(_tintOf('Setting 13'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(_tintOf('Setting 13'), findsOneWidget);

      // After ~2 s it fades out and stays off.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_tintOf('Setting 13'), findsNothing);
      expect(find.text('Setting 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
