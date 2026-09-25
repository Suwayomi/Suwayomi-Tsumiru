import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/koreader_sync_settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class KoSyncLink extends Link {
  KoSyncLink({this.connectSucceeds = true});

  final bool connectSucceeds;
  bool loggedIn = false;
  final operations = <String>[];

  Map<String, dynamic> get _status => {
    '__typename': 'KoSyncStatusPayload',
    'isLoggedIn': loggedIn,
    'serverAddress': loggedIn ? 'http://example' : null,
    'username': loggedIn ? 'tsumiru' : null,
  };

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(name);
    if (name == 'KoSyncStatus') {
      yield Response(
        response: {},
        data: {'__typename': 'Query', 'koSyncStatus': _status},
      );
      return;
    }
    if (name == 'KoreaderSyncLegacySettings') {
      yield Response(
        response: {},
        errors: [
          const GraphQLError(
            message:
                "Validation error (FieldUndefined@[settings/koreaderSyncChecksumMethod]) : Field 'koreaderSyncChecksumMethod' in type 'SettingsType' is undefined",
          ),
        ],
      );
      return;
    }
    if (name == 'ConnectKoSyncAccount') {
      if (connectSucceeds) loggedIn = true;
      yield Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'connectKoSyncAccount': {
            '__typename': 'KoSyncConnectPayload',
            'message': connectSucceeds
                ? null
                : 'Incorrect username or password',
            'status': _status,
          },
        },
      );
      return;
    }
    throw StateError('Unexpected operation $name');
  }
}

KoreaderSyncSettings settingsFixture() => (
  strategyForward: Enum$KoreaderSyncConflictStrategy.PROMPT,
  strategyBackward: Enum$KoreaderSyncConflictStrategy.PROMPT,
  checksumMethod: Enum$KoreaderSyncChecksumMethod.BINARY,
  percentageTolerance: 1e-15,
);

Future<void> pumpScreen(
  WidgetTester tester,
  Link link, {
  List<Override> overrides = const [],
  bool overrideSettings = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = GraphQLClient(
    link: link,
    cache: GraphQLCache(store: InMemoryStore()),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(client),
        if (overrideSettings)
          koreaderSyncSettingsProvider.overrideWith(
            (ref) async => settingsFixture(),
          ),
        ...overrides,
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: KoreaderSyncSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openConnectDialog(WidgetTester tester) async {
  await tester.tap(find.text('Sync status'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Disconnected and the four settings rows', (tester) async {
    await pumpScreen(tester, KoSyncLink());

    expect(find.text('KOReader Sync'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Sync to a newer state'), findsOneWidget);
    expect(find.text('Sync to an older state'), findsOneWidget);
    expect(find.text('Document matching method'), findsOneWidget);
    expect(find.text('Percentage tolerance'), findsOneWidget);
    expect(find.text('Prompt'), findsNWidgets(2));
    expect(find.text('Binary'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a server without KOReader Sync fields shows the update message', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      KoSyncLink(),
      overrideSettings: false,
      overrides: [
        settledAccountAccessProvider.overrideWithValue(
          AccountAccess(capability: AccountCapability.unsupported),
        ),
      ],
    );

    expect(
      find.text(
        'This server does not support KOReader Sync. Update Suwayomi to use it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed connect keeps the dialog open and saves nothing', (
    tester,
  ) async {
    final link = KoSyncLink(connectSucceeds: false);
    await pumpScreen(tester, link);
    await openConnectDialog(tester);

    expect(find.text('Connect to KOReader Sync server'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'tsumiru');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to KOReader Sync server'), findsOneWidget);
    expect(find.text('tsumiru'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Failed to connect to KOReader Sync server.'),
      ),
      findsOneWidget,
    );
    expect(link.operations, ['KoSyncStatus', 'ConnectKoSyncAccount']);
  });

  testWidgets('a successful connect shows the connected status', (
    tester,
  ) async {
    final link = KoSyncLink();
    await pumpScreen(tester, link);
    await openConnectDialog(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'http://example');
    await tester.enterText(find.byType(TextFormField).at(1), 'tsumiru');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect to KOReader Sync server'), findsNothing);
    expect(find.text('Connected as tsumiru to http://example'), findsOneWidget);
  });
}
