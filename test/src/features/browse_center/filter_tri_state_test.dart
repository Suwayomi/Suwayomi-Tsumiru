// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:tsumiru/src/features/browse_center/domain/filter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/widgets/filter_to_widget.dart';

void main() {
  Future<List<FilterChange>> pump(WidgetTester tester, TriState state) async {
    final changes = <FilterChange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterToWidget(
            filter: Fragment$PrimitiveFilterDto$$TriStateFilter(
              name: 'Completed',
              tristate: state,
            ),
            currentChanges: const [],
            onChanged: changes.addAll,
          ),
        ),
      ),
    );
    return changes;
  }

  const cases = [
    (TriState.IGNORE, Icons.check_box_outline_blank_rounded, TriState.INCLUDE),
    (TriState.INCLUDE, Icons.check_box_rounded, TriState.EXCLUDE),
    (TriState.EXCLUDE, Icons.disabled_by_default_rounded, TriState.IGNORE),
  ];

  for (final (state, icon, next) in cases) {
    testWidgets('$state shows its own box and taps to $next', (tester) async {
      final changes = await pump(tester, state);

      expect(find.byIcon(icon), findsOneWidget);
      await tester.tap(find.text('Completed'));
      expect(changes.single.triState, next);
    });
  }
}
