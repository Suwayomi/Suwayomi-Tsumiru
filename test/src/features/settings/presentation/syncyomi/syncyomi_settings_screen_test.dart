// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/syncyomi_settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

import '../../../../../helpers/legacy_account_access.dart';

Map<String, dynamic> _settings({
  bool enabled = false,
  String host = '',
  String apiKey = '',
  String interval = 'PT0S',
  bool dataManga = false,
  bool dataChapters = false,
  bool dataCategories = false,
  bool dataHistory = false,
  bool dataTracking = false,
}) => {
  '__typename': 'SettingsType',
  'syncYomiEnabled': enabled,
  'syncYomiHost': host,
  'syncYomiApiKey': apiKey,
  'syncInterval': interval,
  'syncDataManga': dataManga,
  'syncDataChapters': dataChapters,
  'syncDataCategories': dataCategories,
  'syncDataHistory': dataHistory,
  'syncDataTracking': dataTracking,
};

/// Answers the operations the screen sends, and keeps whatever a mutation
/// writes so the next read shows what the server would return.
class _FakeServer extends Link {
  _FakeServer(
    this.settings, {
    this.status,
    this.failHostWrite = false,
    this.supportsSyncYomi = true,
  });

  final Map<String, dynamic> settings;
  Map<String, dynamic>? status;
  final bool failHostWrite;
  final bool supportsSyncYomi;
  final operations = <String>[];
  final writeVariables = <Map<String, dynamic>>[];

  /// Operations that write something, in the order the screen sent them.
  List<String> get writes => operations
      .where(
        (name) => name != 'LastSyncStatus' && name != 'SyncYomiLegacySettings',
      )
      .toList();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(name);
    switch (name) {
      case 'SyncYomiLegacySettings':
        if (!supportsSyncYomi) {
          yield Response(
            response: {},
            errors: [
              const GraphQLError(
                message:
                    "Validation error (FieldUndefined@[settings/syncYomiEnabled]) : Field 'syncYomiEnabled' in type 'SettingsType' is undefined",
              ),
            ],
          );
          return;
        }
        yield Response(
          response: {},
          data: {'__typename': 'Query', 'settings': settings},
        );
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
      case 'UpdateSyncYomiHost' when failHostWrite:
        yield Response(
          response: {},
          errors: [const GraphQLError(message: 'Host rejected')],
        );
      default:
        writeVariables.add(request.variables);
        settings.addAll(Map<String, dynamic>.from(request.variables));
        yield Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'setSettings': {
              '__typename': 'SetSettingsPayload',
              'settings': settings,
            },
          },
        );
    }
  }
}

class _Harness {
  _Harness({
    Map<String, dynamic>? settings,
    Map<String, dynamic>? status,
    bool failHostWrite = false,
    bool supportsSyncYomi = true,
  }) : settings = settings ?? _settings() {
    server = _FakeServer(
      this.settings,
      status: status,
      failHostWrite: failHostWrite,
      supportsSyncYomi: supportsSyncYomi,
    );
    client = GraphQLClient(
      link: server,
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
  }

  final Map<String, dynamic> settings;
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
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        call,
      ) async {
        if (call.method == 'isMaximized') return false;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null),
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(harness.client),
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
      ],
      // Native desktop draws the toolbar in the shell bar above the page.
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                if (showsMergedTopBar(context)) const DesktopTopBar(),
                const Expanded(child: SyncYomiSettingsScreen()),
              ],
            ),
          ),
        ),
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

void main() {
  testWidgets('loads, reports an unsupported server and saves values', (
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

    // A server without the SyncYomi fields says so.
    await _pump(tester, _Harness(supportsSyncYomi: false));

    expect(
      find.text(
        'This server does not support SyncYomi. Update Suwayomi to use it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Host'), findsNothing);

    // Sync data and the interval pickers save their values.
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
    expect(harness.server.writeVariables.last, {
      'syncDataManga': true,
      'syncDataChapters': false,
      'syncDataCategories': false,
      'syncDataHistory': true,
      'syncDataTracking': true,
    });

    // The interval picker keeps an interval it does not offer, and saving a
    // choice writes it.
    final intervalHarness = _Harness(settings: _settings(interval: 'PT2H'));
    await _pump(tester, intervalHarness);
    expect(find.text('Every 2 hours'), findsOneWidget);
    await tester.tap(find.text('Sync interval'));
    await tester.pumpAndSettle();
    expect(find.text('Every 2 hours'), findsWidgets);
    expect(find.text('Every 3 hours'), findsOneWidget);
    expect(find.text('Manual only'), findsOneWidget);
    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    expect(intervalHarness.server.writes, ['UpdateSyncYomiInterval']);
    expect(intervalHarness.server.writeVariables.last['syncInterval'], 'PT3H');
  });
}
