// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags_dialog.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

import '../../../../helpers/legacy_account_access.dart';

class _SpyBackupRepo extends BackupSettingsRepository {
  _SpyBackupRepo()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
        permissions: legacyAccountPermissions,
      );

  BackupFlags? captured;

  @override
  Future<String?> createBackup(BackupFlags flags) async {
    captured = flags;
    return null;
  }
}

void main() {
  testWidgets('create backup sends the flags chosen in the dialog', (
    tester,
  ) async {
    final spy = _SpyBackupRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupSettingsRepositoryProvider.overrideWithValue(spy),
          toastProvider.overrideWithValue(null),
          backupUserSettingsProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final flags = await showBackupFlagsDialog(
                    context,
                    title: 'Create backup',
                  );
                  if (flags != null) await spy.createBackup(flags);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Library entries'), findsOneWidget);
    expect(find.text('Server settings'), findsOneWidget);

    // Turn off exactly one flag — Tracking — and leave the rest on.
    await tester.tap(find.text('Tracking'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      spy.captured,
      const BackupFlags(
        includeManga: true,
        includeCategories: true,
        includeChapters: true,
        includeHistory: true,
        includeTracking: false, // only this one flipped — no cross-wiring
        includeClientData: true,
        includeServerSettings: true,
      ),
    );
  });

  test('backup include/exclude summary gives All, None and a joined list', () {
    List<(String, bool)> entries(List<bool> values) => [
      ('Library entries', values[0]),
      ('Chapters', values[1]),
      ('Tracking', values[2]),
    ];
    ({String include, String exclude}) summarize(List<bool> values) =>
        summarizeBackupFlags(
          entries: entries(values),
          all: 'All',
          none: 'None',
        );

    expect(summarize([true, true, true]), (include: 'All', exclude: 'None'));
    expect(summarize([false, false, false]), (include: 'None', exclude: 'All'));
    expect(summarize([true, false, true]), (
      include: 'Library entries, Tracking',
      exclude: 'Chapters',
    ));
  });
}
