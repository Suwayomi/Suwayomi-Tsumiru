// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_and_restore/widgets/create_backup_dialog.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/widgets/async_buttons/async_elevated_button.dart';

class _SpyBackupRepo extends BackupSettingsRepository {
  _SpyBackupRepo()
      : super(GraphQLClient(link: HttpLink('http://localhost:0'),
            cache: GraphQLCache()));

  Map<String, bool>? captured;

  @override
  Future<String?> createBackup({
    required bool includeCategories,
    required bool includeChapters,
    required bool includeHistory,
    required bool includeTracking,
    required bool includeClientData,
  }) async {
    captured = {
      'categories': includeCategories,
      'chapters': includeChapters,
      'history': includeHistory,
      'tracking': includeTracking,
      'clientData': includeClientData,
    };
    return null; // blank url → dialog returns before the launch/nav path
  }
}

void main() {
  testWidgets('each checkbox maps to its own backup flag', (tester) async {
    final spy = _SpyBackupRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupSettingsRepositoryProvider.overrideWithValue(spy),
          toastProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CreateBackupDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Turn off exactly one flag — Tracking — and leave the rest on.
    await tester.tap(find.text('Tracking'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AsyncElevatedButton));
    await tester.pumpAndSettle();

    expect(spy.captured, {
      'categories': true,
      'chapters': true,
      'history': true,
      'tracking': false, // only this one flipped — no cross-wiring
      'clientData': true,
    });
  });
}
