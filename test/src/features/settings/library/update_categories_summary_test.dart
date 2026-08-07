// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/library/widgets/update_categories_dialog.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

CategoryDto _cat(int id, String name, Enum$IncludeOrExclude includeInUpdate) =>
    Fragment$CategoryDto(
      defaultCategory: false,
      id: id,
      includeInDownload: Enum$IncludeOrExclude.UNSET,
      includeInUpdate: includeInUpdate,
      name: name,
      order: id,
      mangas: Fragment$CategoryDto$mangas(totalCount: 0),
      meta: const [],
    );

/// Pumps a throwaway widget so we get a real BuildContext with the app's
/// localizations, then evaluates [libraryUpdateCategoriesSummary] against it.
Future<String> _summaryFor(
    WidgetTester tester, List<CategoryDto> categories) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          result = libraryUpdateCategoriesSummary(context, categories);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return result;
}

void main() {
  group('libraryUpdateCategoriesSummary', () {
    testWidgets('reports "All categories" when nothing is set', (tester) async {
      final summary = await _summaryFor(tester, [
        _cat(1, 'Action', Enum$IncludeOrExclude.UNSET),
        _cat(2, 'Comedy', Enum$IncludeOrExclude.UNSET),
      ]);
      expect(summary, 'All categories');
    });

    testWidgets('reports "All categories" for an empty list', (tester) async {
      final summary = await _summaryFor(tester, const []);
      expect(summary, 'All categories');
    });

    testWidgets('lists included and excluded categories', (tester) async {
      final summary = await _summaryFor(tester, [
        _cat(1, 'Action', Enum$IncludeOrExclude.INCLUDE),
        _cat(2, 'Comedy', Enum$IncludeOrExclude.EXCLUDE),
        _cat(3, 'Drama', Enum$IncludeOrExclude.UNSET),
      ]);
      expect(summary, 'Included: Action · Excluded: Comedy');
    });

    testWidgets('only included when nothing is excluded', (tester) async {
      final summary = await _summaryFor(tester, [
        _cat(1, 'Action', Enum$IncludeOrExclude.INCLUDE),
        _cat(2, 'Comedy', Enum$IncludeOrExclude.INCLUDE),
      ]);
      expect(summary, 'Included: Action, Comedy');
    });
  });
}
