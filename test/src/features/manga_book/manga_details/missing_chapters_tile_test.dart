// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/missing_chapters_tile.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('list notice uses singular and plural copy', (tester) async {
    await tester.pumpWidget(_app(const MissingChaptersListTile(count: 1)));
    expect(find.text('Missing 1 chapter'), findsOneWidget);

    await tester.pumpWidget(_app(const MissingChaptersListTile(count: 3)));
    expect(find.text('Missing 3 chapters'), findsOneWidget);
  });

  testWidgets('grid notice shows the count and full message in its tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox.square(
          dimension: 64,
          child: MissingChaptersGridTile(count: 3),
        ),
      ),
    );

    expect(find.text('Missing 3 chapters'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Missing 3 chapters',
    );
    expect(find.byType(InkWell), findsNothing);
  });
}
