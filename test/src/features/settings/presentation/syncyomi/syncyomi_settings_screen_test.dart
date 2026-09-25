// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/syncyomi_settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/legacy_account_access.dart';

Fragment$SettingsDto _settings({
  bool enabled = false,
  String host = '',
  String apiKey = '',
  String interval = 'PT0S',
  bool dataManga = false,
  bool dataChapters = false,
  bool dataCategories = false,
  bool dataHistory = false,
  bool dataTracking = false,
}) => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '',
  port: 0,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 0,
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
  syncDataCategories: dataCategories,
  syncDataChapters: dataChapters,
  syncDataHistory: dataHistory,
  syncDataManga: dataManga,
  syncDataTracking: dataTracking,
  syncInterval: interval,
  syncYomiApiKey: apiKey,
  syncYomiEnabled: enabled,
  syncYomiHost: host,
);

class _FixedSettings extends Settings {
  _FixedSettings(this.settings);

  final Fragment$SettingsDto settings;

  @override
  Future<Fragment$SettingsDto?> build() async => settings;
}

/// Answers the three operations the screen sends, and echoes any setting a
/// mutation writes so the screen shows what the server would return.
class _FakeServer extends Link {
  _FakeServer(this.settings, {this.status});

  final Fragment$SettingsDto settings;
  Map<String, dynamic>? status;
  final operations = <String>[];
  final variables = <Map<String, dynamic>>[];

  /// Operations other than the status poll, in the order the screen sent them.
  List<String> get writes =>
      operations.where((name) => name != 'LastSyncStatus').toList();

  Map<String, dynamic> get settingsJson =>
      Map<String, dynamic>.from(settings.toJson());

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(name);
    variables.add(request.variables);
    switch (name) {
      case 'LastSyncStatus':
        yield Response(
          response: {},
          data: {'__typename': 'Query', 'lastSyncStatus': status},
        );
      case 'StartSync':
        yield Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'startSync': {
              '__typename': 'StartSyncPayload',
              'result': 'SUCCESS',
            },
          },
        );
      default:
        final written = settingsJson
          ..addAll(Map<String, dynamic>.from(request.variables));
        yield Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'setSettings': {
              '__typename': 'SetSettingsPayload',
              'settings': written,
            },
          },
        );
    }
  }
}

class _Harness {
  _Harness({Fragment$SettingsDto? settings, Map<String, dynamic>? status})
    : settings = settings ?? _settings() {
    server = _FakeServer(this.settings, status: status);
    client = GraphQLClient(
      link: server,
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
  }

  final Fragment$SettingsDto settings;
  late final _FakeServer server;
  late final GraphQLClient client;
}

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(harness.client),
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        settingsProvider.overrideWith(() => _FixedSettings(harness.settings)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SyncYomiSettingsScreen(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

ListTile _tileWith(WidgetTester tester, String text) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, text));

int _statusPolls(_Harness harness) =>
    harness.server.operations.where((name) => name == 'LastSyncStatus').length;

void main() {
  testWidgets('shows every setting, unset until the server has them', (
    tester,
  ) async {
    await _pump(tester, _Harness());

    expect(find.text('SyncYomi'), findsWidgets);
    expect(find.text('Sync with SyncYomi'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Sync interval'), findsOneWidget);
    expect(find.text('Sync data'), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Not set'), findsNWidgets(2));
    expect(find.text('Manual only'), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
  });

  testWidgets('Sync data lists what a sync carries and saves all five', (
    tester,
  ) async {
    final harness = _Harness(
      settings: _settings(dataManga: true, dataHistory: true),
    );
    await _pump(tester, harness);
    expect(find.text('Include: Library entries, History'), findsOneWidget);

    await tester.tap(find.text('Sync data'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(5));

    await tester.tap(find.text('Tracking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(harness.server.writes, ['UpdateSyncYomiData']);
    expect(harness.server.variables.last, {
      'syncDataManga': true,
      'syncDataChapters': false,
      'syncDataCategories': false,
      'syncDataHistory': true,
      'syncDataTracking': true,
    });
  });

  testWidgets('Sync now is disabled while the switch, host or key is missing', (
    tester,
  ) async {
    await _pump(tester, _Harness());
    expect(_tileWith(tester, 'Sync now').enabled, isFalse);

    await _pump(
      tester,
      _Harness(settings: _settings(host: 'https://syncyomi.example.com')),
    );
    expect(_tileWith(tester, 'Sync now').enabled, isFalse);

    await _pump(
      tester,
      _Harness(
        settings: _settings(host: 'https://syncyomi.example.com', apiKey: 'k'),
      ),
    );
    expect(_tileWith(tester, 'Sync now').enabled, isFalse);

    await _pump(
      tester,
      _Harness(
        settings: _settings(
          enabled: true,
          host: 'https://syncyomi.example.com',
          apiKey: 'k',
        ),
      ),
    );
    expect(_tileWith(tester, 'Sync now').enabled, isTrue);
  });

  testWidgets('a host that is not an http(s) URL is refused, not saved', (
    tester,
  ) async {
    final harness = _Harness();
    await _pump(tester, harness);

    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'syncyomi.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a URL starting with http:// or https://'),
      findsOneWidget,
    );
    expect(harness.server.writes, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a saved host is trimmed of whitespace and trailing slashes', (
    tester,
  ) async {
    final harness = _Harness();
    await _pump(tester, harness);

    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '  https://syncyomi.example.com///  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(harness.server.writes, ['UpdateSyncYomiHost']);
    expect(
      harness.server.variables.last['syncYomiHost'],
      'https://syncyomi.example.com',
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('https://syncyomi.example.com'), findsOneWidget);
  });

  testWidgets('the interval picker keeps an interval it does not offer', (
    tester,
  ) async {
    final harness = _Harness(settings: _settings(interval: 'PT2H'));
    await _pump(tester, harness);

    expect(find.text('Every 2 hours'), findsOneWidget);
    await tester.tap(find.text('Sync interval'));
    await tester.pumpAndSettle();
    expect(find.text('Every 2 hours'), findsWidgets);
    expect(find.text('Every 3 hours'), findsOneWidget);
    expect(find.text('Manual only'), findsOneWidget);

    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    expect(harness.server.writes, ['UpdateSyncYomiInterval']);
    expect(harness.server.variables.last['syncInterval'], 'PT3H');
  });

  testWidgets('the status line follows the last sync state', (tester) async {
    await _pump(
      tester,
      _Harness(
        status: {
          '__typename': 'SyncStatus',
          'state': 'SUCCESS',
          'errorMessage': null,
          'startDate': '1700000000000',
          'endDate': '1700000001000',
        },
      ),
    );
    expect(find.textContaining('Last synced'), findsOneWidget);

    await _pump(
      tester,
      _Harness(
        status: {
          '__typename': 'SyncStatus',
          'state': 'ERROR',
          'errorMessage': 'host unreachable',
          'startDate': '1700000000000',
          'endDate': '1700000001000',
        },
      ),
    );
    expect(find.text('Last sync failed: host unreachable'), findsOneWidget);

    await _pump(
      tester,
      _Harness(
        status: {
          '__typename': 'SyncStatus',
          'state': 'DOWNLOADING',
          'errorMessage': null,
          'startDate': '1700000000000',
          'endDate': null,
        },
      ),
      settle: false,
    );
    expect(find.text('Syncing: Downloading'), findsOneWidget);
    // The poll timer must not outlive the screen.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sync now asks the server to sync, then polls the status', (
    tester,
  ) async {
    final harness = _Harness(
      settings: _settings(
        enabled: true,
        host: 'https://syncyomi.example.com',
        apiKey: 'k',
      ),
    );
    await _pump(tester, harness, settle: false);
    expect(harness.server.operations, ['LastSyncStatus']);

    await tester.tap(find.text('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.server.writes, ['StartSync']);
    final polls = harness.server.operations
        .where((name) => name == 'LastSyncStatus')
        .length;

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(
      harness.server.operations.where((name) => name == 'LastSyncStatus'),
      hasLength(greaterThan(polls)),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sync started over an old SUCCESS is watched to its own end', (
    tester,
  ) async {
    final harness = _Harness(
      settings: _settings(
        enabled: true,
        host: 'https://syncyomi.example.com',
        apiKey: 'k',
      ),
      status: {
        '__typename': 'SyncStatus',
        'state': 'SUCCESS',
        'errorMessage': null,
        'startDate': '1',
        'endDate': '1700000001000',
      },
    );
    await _pump(tester, harness, settle: false);
    expect(find.textContaining('Last synced'), findsOneWidget);

    await tester.tap(find.text('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.server.writes, ['StartSync']);
    final polls = _statusPolls(harness);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(_statusPolls(harness), greaterThan(polls));

    harness.server.status = {
      '__typename': 'SyncStatus',
      'state': 'SUCCESS',
      'errorMessage': null,
      'startDate': '2',
      'endDate': '1800000001000',
    };
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Last synced'), findsOneWidget);
    final settled = _statusPolls(harness);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(_statusPolls(harness), settled);
    await tester.pumpWidget(const SizedBox());
  });
}
