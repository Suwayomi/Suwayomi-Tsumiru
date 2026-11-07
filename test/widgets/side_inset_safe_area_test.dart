// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsumiru/src/widgets/side_inset_safe_area.dart';

// iPhone Duo outer display, closed, portrait and landscape (logical points).
const _outerPortrait = Size(466, 678);
const _outerLandscape = Size(678, 466);
const _statusColumn = EdgeInsets.only(right: 84, bottom: 34);

const _probe = Key('probe');

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required EdgeInsets padding,
  Widget? child,
  bool belowNavigator = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(
    left: padding.left,
    top: padding.top,
    right: padding.right,
    bottom: padding.bottom,
  );
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);
  final home = child ?? const SizedBox.expand(key: _probe);
  // The app wraps MaterialApp.builder's child, whose Navigator has a GlobalKey
  // and would survive a remount anyway; below the Navigator nothing does.
  await tester.pumpWidget(
    belowNavigator
        ? MaterialApp(home: SideInsetSafeArea(child: home))
        : MaterialApp(
            builder: (context, child) => SideInsetSafeArea(child: child!),
            home: home,
          ),
  );
}

void main() {
  testWidgets('compact window keeps content out of a side status column', (
    tester,
  ) async {
    await _pump(tester, size: _outerPortrait, padding: _statusColumn);

    final rect = tester.getRect(find.byKey(_probe));
    expect(rect.left, 0);
    expect(rect.right, 466 - 84);
    expect(rect.bottom, 678, reason: 'bottom inset is left to the page');

    final inner = MediaQuery.of(tester.element(find.byKey(_probe)));
    expect(inner.padding.right, 0, reason: 'consumed, not applied twice');
    expect(inner.padding.bottom, 34);
  });

  testWidgets('no side insets: compact layout is unchanged', (tester) async {
    await _pump(
      tester,
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 47, bottom: 34),
    );

    expect(
      tester.getRect(find.byKey(_probe)),
      Offset.zero & const Size(390, 844),
    );
  });

  testWidgets('medium window is left to the shell SafeArea', (tester) async {
    await _pump(tester, size: _outerLandscape, padding: _statusColumn);

    expect(tester.getRect(find.byKey(_probe)).width, 678);
    final inner = MediaQuery.of(tester.element(find.byKey(_probe)));
    expect(inner.padding.right, 84, reason: 'still visible to the shell');
  });

  testWidgets('rotating across the breakpoint keeps child state', (
    tester,
  ) async {
    await _pump(
      tester,
      size: _outerPortrait,
      padding: _statusColumn,
      child: const _Counter(),
      belowNavigator: true,
    );
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    tester.view.physicalSize = _outerLandscape;
    await tester.pump();
    expect(find.text('1'), findsOneWidget, reason: 'state survived');

    tester.view.physicalSize = _outerPortrait;
    await tester.pump();
    expect(find.text('1'), findsOneWidget, reason: 'state survived');
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('$count'),
    ),
  );
}
