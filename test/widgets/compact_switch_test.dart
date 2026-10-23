// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/compact_switch.dart';

const _desktop = Size(1280, 800);
const _phone = Size(390, 844);

Future<void> _pump(WidgetTester tester, Widget child, Size surface) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

List<Size> _sizedBoxSizes(WidgetTester tester) => tester
    .widgetList<SizedBox>(find.byType(SizedBox))
    .map((w) => tester.getSize(find.byWidget(w)))
    .toList();

void main() {
  testWidgets('desktop CompactSwitch draws at 75% with natural child layout', (
    tester,
  ) async {
    await _pump(
      tester,
      const Column(children: [CompactSwitch(value: true, onChanged: null)]),
      _desktop,
    );
    expect(
      tester.getSize(find.byType(CompactSwitch)),
      const Size(45, 36),
      reason: '60x48 switch at 0.75 scale',
    );
    expect(
      tester.getSize(find.byType(Switch)),
      const Size(60, 48),
      reason: 'FittedBox lays the switch out at full size, then scales paint',
    );
  });

  testWidgets('desktop tile keeps row height and shrinks only the switch', (
    tester,
  ) async {
    bool? toggledWith;
    await _pump(
      tester,
      Column(
        children: [
          CompactSwitchListTile(
            value: false,
            onChanged: (v) => toggledWith = v,
            title: const Text('t'),
          ),
        ],
      ),
      _desktop,
    );
    expect(
      tester.getSize(find.byType(CompactSwitchListTile)).height,
      56,
      reason: 'same height as a plain SwitchListTile row',
    );
    expect(
      _sizedBoxSizes(tester),
      contains(const Size(45, 30)),
      reason: '60x40 tile switch at 0.75 scale',
    );
    expect(
      tester.getSize(find.byType(Switch)),
      const Size(60, 40),
      reason: 'inner switch keeps its natural layout size',
    );

    await tester.tap(find.text('t'));
    expect(toggledWith, true);

    toggledWith = null;
    await tester.tap(find.byType(Switch));
    expect(toggledWith, true, reason: 'scaled switch still hit-tests taps');
  });

  testWidgets('desktop disabled tile stays disabled', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          CompactSwitchListTile(
            value: false,
            onChanged: null,
            title: Text('t'),
          ),
        ],
      ),
      _desktop,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
  });

  testWidgets('phone sizes are identical to plain Switch widgets', (
    tester,
  ) async {
    await _pump(
      tester,
      const Column(children: [CompactSwitch(value: true, onChanged: null)]),
      _phone,
    );
    final compactSwitch = tester.getSize(find.byType(CompactSwitch));

    await _pump(
      tester,
      const Column(children: [Switch(value: true, onChanged: null)]),
      _phone,
    );
    expect(tester.getSize(find.byType(Switch)), compactSwitch);

    await _pump(
      tester,
      const Column(
        children: [
          CompactSwitchListTile(value: true, onChanged: null, title: Text('t')),
        ],
      ),
      _phone,
    );
    final compactTile = tester.getSize(find.byType(CompactSwitchListTile));

    await _pump(
      tester,
      const Column(
        children: [
          SwitchListTile(value: true, onChanged: null, title: Text('t')),
        ],
      ),
      _phone,
    );
    expect(tester.getSize(find.byType(SwitchListTile)), compactTile);
  });
}
