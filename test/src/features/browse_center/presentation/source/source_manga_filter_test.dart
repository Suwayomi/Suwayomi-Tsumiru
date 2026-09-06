// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/source_manga_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/widgets/source_manga_filter.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Filter _checkBox(String name) => Filter.fromJson({
      '__typename': 'CheckBoxFilter',
      'name': name,
      'checkBoxState': false,
    });

Filter _group(String name, List<String> children) => Filter.fromJson({
      '__typename': 'GroupFilter',
      'name': name,
      'groupState': [
        for (final child in children)
          {
            '__typename': 'CheckBoxFilter',
            'name': child,
            'checkBoxState': false,
          },
      ],
    });

Widget _harness({
  required List<Filter> filters,
  required List<FilterChange> appliedChanges,
  ValueChanged<List<FilterChange>?>? onSubmitted,
  VoidCallback? onReset,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SourceMangaFilter(
        filters: filters,
        sourceId: '1',
        appliedChanges: appliedChanges,
        onSubmitted: onSubmitted ?? (_) {},
        onReset: onReset ?? () {},
      ),
    );

bool _boxValue(WidgetTester tester, String title) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, title))
    .value!;

void main() {
  testWidgets('an applied filter shows as ticked when the sheet opens',
      (tester) async {
    await tester.pumpWidget(_harness(
      filters: [_checkBox('Completed'), _checkBox('Licensed')],
      appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
    ));
    await tester.pump();

    expect(_boxValue(tester, 'Completed'), isTrue);
    expect(_boxValue(tester, 'Licensed'), isFalse);
  });

  testWidgets('the sheet re-seeds when the applied filters change while mounted',
      (tester) async {
    await tester.pumpWidget(_harness(
      filters: [_checkBox('Completed'), _checkBox('Licensed')],
      appliedChanges: const [],
    ));
    await tester.pump();
    expect(_boxValue(tester, 'Completed'), isFalse);

    await tester.pumpWidget(_harness(
      filters: [_checkBox('Completed'), _checkBox('Licensed')],
      appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
    ));
    await tester.pump();

    expect(_boxValue(tester, 'Completed'), isTrue);
  });

  testWidgets('applying a second filter keeps the one already applied',
      (tester) async {
    List<FilterChange>? submitted;
    await tester.pumpWidget(_harness(
      filters: [_checkBox('Completed'), _checkBox('Licensed')],
      appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
      onSubmitted: (value) => submitted = value,
    ));
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

  testWidgets('reset clears the ticks and tells the screen to drop the filters',
      (tester) async {
    var resetCalls = 0;
    await tester.pumpWidget(_harness(
      filters: [_checkBox('Completed')],
      appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
      onReset: () => resetCalls++,
    ));
    await tester.pump();
    expect(_boxValue(tester, 'Completed'), isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pump();

    expect(resetCalls, 1);
    expect(_boxValue(tester, 'Completed'), isFalse);
  });

  testWidgets('a filter applied inside a group is still ticked on reopen',
      (tester) async {
    await tester.pumpWidget(_harness(
      filters: [_group('Genre', ['Action', 'Comedy'])],
      appliedChanges: [
        FilterChange(
          position: 0,
          groupChange: FilterChange(checkBoxState: true, position: 1),
        ),
      ],
    ));
    await tester.pump();

    await tester.tap(find.text('Genre'));
    await tester.pumpAndSettle();

    expect(_boxValue(tester, 'Action'), isFalse);
    expect(_boxValue(tester, 'Comedy'), isTrue);
  });

  test('applied filters outlive leaving the source and are per source', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final change = FilterChange(checkBoxState: true, position: 0);
    container.read(appliedSourceFilterProvider('1').notifier).apply([change]);

    container.listen(appliedSourceFilterProvider('1'), (_, _) {}).close();

    expect(container.read(appliedSourceFilterProvider('1')), [change]);
    expect(container.read(appliedSourceFilterProvider('2')), isEmpty);

    container.read(appliedSourceFilterProvider('1').notifier).reset();
    expect(container.read(appliedSourceFilterProvider('1')), isEmpty);
  });
}
