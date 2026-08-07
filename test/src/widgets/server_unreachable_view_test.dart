// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

Future<ProviderContainer> _pump(WidgetTester tester,
    {VoidCallback? onRetry,
    bool hasCatalog = false,
    bool offlineEscape = true}) async {
  final container = ProviderContainer(overrides: [
    offlineCatalogAvailableProvider.overrideWith((ref) async => hasCatalog),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: ServerUnreachableView(
                onRetry: onRetry, offlineEscape: offlineEscape)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Unmounts the tree and flushes Riverpod's zero-length auto-dispose timer,
/// which otherwise trips the pending-timer invariant at test end.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('shows the unreachable message and a Connection settings action',
      (tester) async {
    await _pump(tester);

    expect(find.text("Can't reach your server"), findsOneWidget);
    expect(find.text('Connection settings'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('no retry button without a retry callback', (tester) async {
    await _pump(tester);
    expect(find.text('Refresh'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('retry button shows and fires when provided', (tester) async {
    var retried = 0;
    await _pump(tester, onRetry: () => retried++);
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    await _unmount(tester);
  });

  testWidgets('no View offline without a catalog', (tester) async {
    await _pump(tester);
    expect(find.text('View offline'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('no View offline on screens that ignore the pin',
      (tester) async {
    await _pump(tester, hasCatalog: true, offlineEscape: false);
    expect(find.text('View offline'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('View offline shows with a catalog and sets the pin',
      (tester) async {
    final container = await _pump(tester, hasCatalog: true);
    expect(find.text('View offline'), findsOneWidget);

    await tester.tap(find.text('View offline'));
    await tester.pumpAndSettle();
    expect(container.read(viewOfflineNowProvider), isTrue);
    await _unmount(tester);
  });
}
