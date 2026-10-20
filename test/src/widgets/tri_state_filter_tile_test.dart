// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/tri_state_filter_tile.dart';

/// Stands in for a `bool?` preference provider.
final _filter = NotifierProvider<_FilterNotifier, bool?>(_FilterNotifier.new);

class _FilterNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;
  void set(bool? value) => state = value;
}

Future<List<bool?>> _pump(
  WidgetTester tester, {
  bool? initial,
  String? includedLabel,
  String? excludedLabel,
}) async {
  final changes = <bool?>[];
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(_filter.notifier).set(initial);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: TriStateFilterTile(
            header: 'Download Status',
            provider: _filter,
            includedLabel: includedLabel,
            excludedLabel: excludedLabel,
            onChanged: (v) {
              changes.add(v);
              container.read(_filter.notifier).set(v);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return changes;
}

void main() {
  group('TriStateFilterTile', () {
    /// Which pill reads as selected.
    Set<String> selectedLabels(WidgetTester tester) => {
      for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip)))
        if (chip.selected) ((chip.label as Text).data)!,
    };

    testWidgets('exactly one pill is selected and taps write their state', (
      tester,
    ) async {
      for (final initial in <bool?>[null, true, false]) {
        await _pump(tester, initial: initial);
        expect(selectedLabels(tester), hasLength(1));
      }

      // Each pill writes its own state, one tap, no cycling.
      final changes = await _pump(tester, initial: null);
      await tester.tap(find.text('Excluded'));
      await tester.pump();
      expect(changes, [false]);
      await tester.tap(find.text('Included'));
      await tester.pump();
      expect(changes, [false, true]);
      await tester.tap(find.text('Any'));
      await tester.pump();
      expect(changes, [false, true, null]);

      // Re-tapping the active pill is idempotent.
      await _pump(tester, initial: true);
      await tester.tap(find.text('Included'));
      await tester.pump();
      expect(selectedLabels(tester), {'Included'});

      // Custom-labelled pills still write the right value.
      final custom = await _pump(
        tester,
        includedLabel: 'Downloaded',
        excludedLabel: 'Not Downloaded',
      );
      await tester.tap(find.text('Downloaded'));
      await tester.pump();
      expect(custom, [true]);
      await tester.tap(find.text('Not Downloaded'));
      await tester.pump();
      expect(custom, [true, false]);
    });
  });
}
