// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Typing in search rebuilds the results per keystroke. The GraphQL-backed
// providers settings search reads must survive those rebuilds: at most one
// fetch per provider while the search is open, none when already loaded.
// This pumps a search host through five queries — alternating a query that
// matches ten local rows early (so matching never reaches the server
// entries) with one that scans everything — and asserts no server-backed
// provider builds more than once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';

SettingsDto _loadedSettings() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '0.0.0.0',
  port: 4567,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 5,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  extensionRepos: const [],
  maxSourcesInParallel: 0,
  localSourcePath: '',
  globalUpdateInterval: 12,
  updateMangas: false,
  excludeCompleted: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  downloadAsCbz: false,
  downloadsPath: '',
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeEntryWithUnreadChapters: false,
);

class _LoadedSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _loadedSettings();
}

/// A search host in miniature: pins the server-backed providers, then
/// matches like the phone overlay and desktop dropdown do.
class _SearchHost extends ConsumerWidget {
  const _SearchHost({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    pinSettingsSearchProviders(ref);
    matchSettingsEntries(
      entries: allSettingsSearchEntries,
      l: AppLocalizationsEn(),
      query: query,
      isVisible: (e) => e.visible(ref, context),
    );
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('typing five queries builds each server provider at most once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    var settingsBuilds = 0;
    var webBuilds = 0;
    var syncBuilds = 0;
    var koreaderBuilds = 0;
    var koSyncBuilds = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        settledAccountAccessProvider.overrideWithValue(
          AccountAccess(capability: AccountCapability.unsupported),
        ),
        settingsProvider.overrideWith(() {
          settingsBuilds++;
          return _LoadedSettings();
        }),
        webInterfaceSettingsProvider.overrideWith((ref) async {
          webBuilds++;
          return null;
        }),
        syncYomiSettingsProvider.overrideWith((ref) async {
          syncBuilds++;
          return null;
        }),
        koreaderSyncSettingsProvider.overrideWith((ref) async {
          koreaderBuilds++;
          return null;
        }),
        koSyncStatusProvider.overrideWith((ref) async {
          koSyncBuilds++;
          return const KoSyncStatus(isLoggedIn: false);
        }),
      ],
    );
    addTearDown(container.dispose);

    Future<void> typeQuery(String query) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _SearchHost(query: query),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    // Alternate a query that fills the 10-hit cap on local rows (server
    // entries never evaluated, their subscriptions would drop without the
    // pin) with one that scans the whole registry.
    for (final query in ['a', 'zzzqx', 'a', 'zzzqx', 'a']) {
      await typeQuery(query);
    }
    await tester.pumpAndSettle();

    expect(settingsBuilds, lessThanOrEqualTo(1));
    expect(webBuilds, lessThanOrEqualTo(1));
    expect(syncBuilds, lessThanOrEqualTo(1));
    expect(koreaderBuilds, lessThanOrEqualTo(1));
    expect(koSyncBuilds, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });
}
