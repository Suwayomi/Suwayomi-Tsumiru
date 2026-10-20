// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/widgets/source_manga_filter.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Filter _checkBox(String name) => Filter.fromJson({
  '__typename': 'CheckBoxFilter',
  'name': name,
  'checkBoxState': false,
});

Widget _harness({
  required List<Filter> filters,
  required List<FilterChange> appliedChanges,
  ValueChanged<List<FilterChange>?>? onSubmitted,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SourceMangaFilter(
    filters: filters,
    sourceId: '1',
    appliedChanges: appliedChanges,
    onSubmitted: onSubmitted ?? (_) {},
    onReset: () {},
  ),
);

void main() {
  testWidgets('applying a second filter keeps the one already applied', (
    tester,
  ) async {
    List<FilterChange>? submitted;
    await tester.pumpWidget(
      _harness(
        filters: [_checkBox('Completed'), _checkBox('Licensed')],
        appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
        onSubmitted: (value) => submitted = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Licensed'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Filter'));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(
      submitted,
      containsAll(<FilterChange>[
        FilterChange(checkBoxState: true, position: 0),
        FilterChange(checkBoxState: true, position: 1),
      ]),
    );
  });
}
