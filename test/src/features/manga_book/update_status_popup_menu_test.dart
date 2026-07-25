// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/widgets/update_status_popup_menu.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

// showDuplicatesButton is opt-in (default false) so the item only leaks into
// the two library app bars, never Updates or the summary sheet. Passing null
// omits the constructor argument entirely, so the default-flag test actually
// exercises the default rather than an explicit false.
Widget _harness({required bool? showDuplicatesButton}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            actions: [
              showDuplicatesButton == null
                  ? const UpdateStatusPopupMenu()
                  : UpdateStatusPopupMenu(
                      showDuplicatesButton: showDuplicatesButton,
                    ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/library-duplicates',
        builder: (context, state) =>
            const Scaffold(body: Text('DUPLICATES SCREEN')),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showDuplicatesButton true: item present and pushes the route',
      (tester) async {
    await tester.pumpWidget(_harness(showDuplicatesButton: true));
    await _openMenu(tester);

    expect(find.text('Scan for duplicates'), findsOneWidget);

    await tester.tap(find.text('Scan for duplicates'));
    await tester.pumpAndSettle();

    expect(find.text('DUPLICATES SCREEN'), findsOneWidget);
  });

  testWidgets('default (flag omitted): item absent', (tester) async {
    await tester.pumpWidget(_harness(showDuplicatesButton: null));
    await _openMenu(tester);

    expect(find.text('Scan for duplicates'), findsNothing);
  });
}
