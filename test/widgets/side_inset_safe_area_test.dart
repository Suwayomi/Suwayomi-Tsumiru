// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

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

  _stylerTests();
}

Color _insetFill(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(SideInsetSafeArea),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

const _reader = Key('reader');

Widget _readerPage({required bool drawUnder}) => Scaffold(
  body: Stack(
    children: [
      SideInsetStyler(
        style: SideInsetStyle(fill: Colors.black, drawUnder: drawUnder),
        child: const SizedBox.shrink(),
      ),
      const SizedBox.expand(key: _reader),
    ],
  ),
);

Future<void> _settle(WidgetTester tester) async {
  // Styles land after the frame that changed them, then rebuild.
  await tester.pump();
  await tester.pump();
}

void _stylerTests() {
  testWidgets('a screen can paint the inset its own colour', (tester) async {
    await _pump(
      tester,
      size: _outerPortrait,
      padding: _statusColumn,
      child: _readerPage(drawUnder: false),
    );
    await _settle(tester);

    expect(_insetFill(tester), Colors.black);
    expect(tester.getRect(find.byKey(_reader)).right, 466 - 84);
  });

  testWidgets('drawUnder hands the insets to the screen', (tester) async {
    await _pump(
      tester,
      size: _outerPortrait,
      padding: _statusColumn,
      child: _readerPage(drawUnder: true),
    );
    await _settle(tester);

    expect(tester.getRect(find.byKey(_reader)).right, 466);
    final inner = MediaQuery.of(tester.element(find.byKey(_reader)));
    expect(inner.padding.right, 84, reason: 'chrome can still avoid it');
  });

  testWidgets('pages below never lay out under the inset while visible', (
    tester,
  ) async {
    await _pump(tester, size: _outerPortrait, padding: _statusColumn);
    final home = Theme.of(tester.element(find.byKey(_probe)));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => _readerPage(drawUnder: true)),
      ),
    );
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_insetFill(tester), Colors.black, reason: 'colour from the start');
    expect(tester.getSize(find.byKey(_probe)).width, 466 - 84);

    await tester.pumpAndSettle();
    await _settle(tester);
    expect(tester.getSize(find.byKey(_reader)).width, 466);

    navigator.pop();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(find.byKey(_reader)).width, 466 - 84);
    expect(
      tester.getSize(find.byKey(_probe, skipOffstage: false)).width,
      466 - 84,
    );

    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_insetFill(tester), home.scaffoldBackgroundColor);
  });

  testWidgets('a replaced screen does not clear its successor', (tester) async {
    await _pump(tester, size: _outerPortrait, padding: _statusColumn);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => _readerPage(drawUnder: true)),
      ),
    );
    await tester.pumpAndSettle();
    await _settle(tester);

    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => _readerPage(drawUnder: true)),
      ),
    );
    await tester.pumpAndSettle();
    await _settle(tester);

    expect(_insetFill(tester), Colors.black);
    expect(tester.getRect(find.byKey(_reader)).right, 466);
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
