// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/browse_center/presentation/browse/browse_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Widget _harness(int currentIndex) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BrowseScreen(
          currentIndex: currentIndex,
          onDestinationSelected: (_) {},
          children: const [
            Center(child: Text('sources')),
            Center(child: Text('extensions')),
            Center(child: Text('migrate')),
          ],
        ),
      ),
    );

void main() {
  testWidgets('repo affordance shows on the Extensions tab', (tester) async {
    await tester.pumpWidget(_harness(1));
    await tester.pump();
    expect(find.byTooltip('Extension Repository'), findsOneWidget);
  });

  testWidgets('repo affordance is absent on the Sources tab', (tester) async {
    await tester.pumpWidget(_harness(0));
    await tester.pump();
    expect(find.byTooltip('Extension Repository'), findsNothing);
  });

  testWidgets('Migrate tab shows neither repo nor language affordance',
      (tester) async {
    await tester.pumpWidget(_harness(2));
    await tester.pump();
    expect(find.byTooltip('Extension Repository'), findsNothing);
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
  });
}
