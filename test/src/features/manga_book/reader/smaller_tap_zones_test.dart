// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// "Smaller tap zones": the active edge regions shrink from 0.33 to
// 0.25 of the axis, widening the center dead-zone. Default OFF must be
// byte-identical (thirds); ON shrinks the measured tap-zone geometry.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/layouts/edge_layout.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/layouts/kindlish_layout.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/layouts/l_shaped_layout.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/layouts/right_and_left_layout.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/reader_navigation_layout.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

const _w = 300.0;
const _h = 600.0;

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: _w, height: _h, child: child),
        ),
      ),
    );

/// First GestureDetector = the leading edge zone in every layout.
Size _firstZone(WidgetTester tester) =>
    tester.getSize(find.byType(GestureDetector).first);

void main() {
  group('smaller tap zones — layout geometry', () {
    testWidgets('EdgeLayout edge width: 1/3 → 1/4', (tester) async {
      await _pump(tester, const EdgeLayout());
      expect(_firstZone(tester).width, closeTo(_w / 3, 0.01));

      await _pump(tester, const EdgeLayout(smaller: true));
      expect(_firstZone(tester).width, closeTo(_w / 4, 0.01));
    });

    testWidgets('RightAndLeftLayout edge width: 1/3 → 1/4', (tester) async {
      await _pump(tester, const RightAndLeftLayout());
      expect(_firstZone(tester).width, closeTo(_w / 3, 0.01));

      await _pump(tester, const RightAndLeftLayout(smaller: true));
      expect(_firstZone(tester).width, closeTo(_w / 4, 0.01));
    });

    testWidgets('KindlishLayout prev width: 1/3 → 1/4', (tester) async {
      await _pump(tester, const KindlishLayout());
      expect(_firstZone(tester).width, closeTo(_w / 3, 0.01));

      await _pump(tester, const KindlishLayout(smaller: true));
      expect(_firstZone(tester).width, closeTo(_w / 4, 0.01));
    });

    testWidgets('LShapedLayout top band height: 1/3 → 1/4', (tester) async {
      await _pump(tester, const LShapedLayout());
      expect(_firstZone(tester).height, closeTo(_h / 3, 0.01));

      await _pump(tester, const LShapedLayout(smaller: true));
      expect(_firstZone(tester).height, closeTo(_h / 4, 0.01));
    });
  });

  group('smaller tap zones — provider threading', () {
    Future<void> pumpWidget(
      WidgetTester tester, {
      required bool pref,
    }) async {
      SharedPreferences.setMockInitialValues(
        pref ? {'smallerTapZones': true} : const {},
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: _w,
                height: _h,
                child: ReaderNavigationLayoutWidget(
                  navigationLayout: ReaderNavigationLayout.edge,
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('pref OFF → edge zone is 1/3 (default)', (tester) async {
      await pumpWidget(tester, pref: false);
      expect(_firstZone(tester).width, closeTo(_w / 3, 0.01));
    });

    testWidgets('pref ON → edge zone shrinks to 1/4', (tester) async {
      await pumpWidget(tester, pref: true);
      expect(_firstZone(tester).width, closeTo(_w / 4, 0.01));
    });
  });
}
