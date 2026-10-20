// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery_state.dart';
import 'package:tsumiru/src/features/offline/presentation/account_storage_recovery_banner.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _RecordingRecovery extends AccountSessionStorage {
  _RecordingRecovery(super.ref, this.saved);
  final List<Map<int, bool>> saved;
  @override
  Future<void> recover({Map<int, bool> progressChoices = const {}}) async {
    saved.add(Map.of(progressChoices));
  }
}

void main() {
  testWidgets(
    'progress conflict requires a choice and retries with that choice',
    (tester) async {
      final saved = <Map<int, bool>>[];
      final container = ProviderContainer(
        overrides: [
          accountSessionStorageProvider.overrideWith(
            (ref) => _RecordingRecovery(ref, saved),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(accountStorageRecoveryProvider.notifier)
          .update(
            const AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.failed,
              conflicts: [
                AccountProgressConflict(
                  chapterId: 7,
                  name: 'Chapter 7',
                  originalPage: 112,
                  currentPage: 0,
                  originalRead: true,
                  currentRead: false,
                  originalBookmarked: false,
                  currentBookmarked: true,
                  originalLastReadAt: '1700000000',
                  originalPendingFields: ['progress_dirty', 'read_state_dirty'],
                  originalReadStateManual: true,
                ),
              ],
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AccountStorageRecoveryBanner()),
          ),
        ),
      );
      await tester.tap(find.text('Review progress'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      expect(find.textContaining('Page: 113'), findsOneWidget);
      expect(find.textContaining('Last read: Not recorded'), findsOneWidget);
      expect(find.textContaining('2023'), findsOneWidget);
      expect(
        find.textContaining('Pending sync: page position, read status'),
        findsOneWidget,
      );
      expect(find.textContaining('No pending changes'), findsOneWidget);
      expect(
        find.textContaining('Read status changed manually'),
        findsOneWidget,
      );
      expect(find.textContaining('Page: 1 · Unread'), findsOneWidget);
      await tester.tap(find.text('Use current'));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, [
        {7: false},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
