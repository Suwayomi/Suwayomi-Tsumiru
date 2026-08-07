// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/organizer_heading.dart';
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
  group('FilterState', () {
    test('maps to and from the persisted bool?', () {
      expect(FilterState.fromValue(null), FilterState.any);
      expect(FilterState.fromValue(true), FilterState.included);
      expect(FilterState.fromValue(false), FilterState.excluded);
      expect(FilterState.any.value, isNull);
      expect(FilterState.included.value, isTrue);
      expect(FilterState.excluded.value, isFalse);
    });

    test('round-trips every state', () {
      for (final state in FilterState.values) {
        expect(FilterState.fromValue(state.value), state);
      }
    });
  });

  group('TriStateFilterTile', () {
    testWidgets('names all three states instead of cycling one glyph', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Download Status'), findsOneWidget);
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('Excluded'), findsOneWidget);
      expect(find.byType(FilterChip), findsNWidgets(3));
    });

    testWidgets('a contextual header replaces the generic title', (
      tester,
    ) async {
      // The heading names the AXIS ("Read Status"), not a repeated value.
      await _pump(tester);
      expect(find.byType(OrganizerHeading), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(OrganizerHeading),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Download Status',
      );
    });

    testWidgets('custom included/excluded labels override the generic ones', (
      tester,
    ) async {
      await _pump(
        tester,
        includedLabel: 'Downloaded',
        excludedLabel: 'Not Downloaded',
      );
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Not Downloaded'), findsOneWidget);
      expect(find.text('Included'), findsNothing);
      expect(find.text('Excluded'), findsNothing);
    });

    testWidgets('tapping a custom-labelled pill still writes the right value', (
      tester,
    ) async {
      final changes = await _pump(
        tester,
        includedLabel: 'Downloaded',
        excludedLabel: 'Not Downloaded',
      );
      await tester.tap(find.text('Downloaded'));
      await tester.pump();
      expect(changes, [true]);

      await tester.tap(find.text('Not Downloaded'));
      await tester.pump();
      expect(changes, [true, false]);
    });

    /// Which pill reads as selected.
    Set<String> selectedLabels(WidgetTester tester) => {
      for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip)))
        if (chip.selected) ((chip.label as Text).data)!,
    };

    testWidgets('exactly one pill is ever selected', (tester) async {
      for (final initial in <bool?>[null, true, false]) {
        await _pump(tester, initial: initial);
        expect(selectedLabels(tester), hasLength(1));
      }
    });

    testWidgets('each pill writes its own state, with no cycling', (
      tester,
    ) async {
      // The whole point over the old tri-state checkbox: picking a state is one
      // tap on that state, not N taps through a hidden order.
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
    });

    testWidgets('re-tapping the active pill is idempotent', (tester) async {
      final changes = await _pump(tester, initial: true);
      await tester.tap(find.text('Included'));
      await tester.pump();
      expect(changes, [true]);
      expect(selectedLabels(tester), {'Included'});
    });
  });
}
