// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Regression guard for #350: the library's global-search button replaced the
// navigation stack, so global search opened with the shell gone and nothing
// underneath. There was no back entry and no bottom nav, and closing the app
// was the only way back to the library.
//
// The route topology here mirrors the real one: the library lives inside the
// shell, global search is a top-level sibling of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tsumiru/src/routes/navigation.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/library/0',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          Scaffold(body: child, bottomNavigationBar: const Text('BOTTOM NAV')),
      routes: [
        GoRoute(
          path: '/library/:categoryId',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => openGlobalSearch(context, query: 'king'),
                child: const Text('global search'),
              ),
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/global-search',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('GLOBAL SEARCH'))),
    ),
  ],
);

void main() {
  group('opening global search from the library', () {
    testWidgets('leaves a route to come back to', (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('global search'));
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      expect(
        navigator.canPop(),
        isTrue,
        reason: 'go() would replace the stack and strand the reader here',
      );
    });

    testWidgets('going back returns to the library and its nav bar', (
      tester,
    ) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('global search'));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      expect(find.text('GLOBAL SEARCH'), findsNothing);
      expect(find.text('global search'), findsOneWidget);
      expect(find.text('BOTTOM NAV'), findsOneWidget);
    });
  });
}
