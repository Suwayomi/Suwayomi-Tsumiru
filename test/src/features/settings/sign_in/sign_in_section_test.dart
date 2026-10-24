import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_stub.dart'
    as pending;
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/sign_in_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

Future<ProviderContainer> pumpSection(
  WidgetTester tester, {
  bool accounts = false,
  int userId = 1,
  Enum$AuthMode mode = Enum$AuthMode.UI_LOGIN,
  bool web = false,
  bool blank = false,
  bool absent = false,
  GraphQLClient? client,
  bool capabilityUnknown = false,
  bool settingsError = false,
  Completer<void>? loading,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  var capabilityReads = 0;
  var settingsReads = 0;
  final container = ProviderContainer(
    overrides: [
      pendingTrackerOAuthStoreProvider.overrideWithValue(
        pending.createPendingTrackerOAuthStore(),
      ),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      if (client != null)
        unauthenticatedGraphQlClientProvider.overrideWithValue(client),
      signInSettingsProvider.overrideWith((ref) async {
        await loading?.future;
        if (settingsError && settingsReads++ == 0) throw StateError('offline');
        return absent
            ? null
            : Fragment$SignInSettingsDto(
                authMode: mode,
                authUsername: blank ? '' : 'admin',
                authPassword: blank ? '' : 'secret',
                jwtAudience: 'suwayomi',
                jwtTokenExpiry: 'PT5M',
                jwtRefreshExpiry: 'PT1440H',
              );
      }),
      signInAccountsCapabilityProvider.overrideWith(
        (ref) async => capabilityUnknown && capabilityReads++ == 0
            ? AccountCapability.unknown
            : accounts
            ? AccountCapability.supported
            : AccountCapability.unsupported,
      ),
      currentAccountProvider.overrideWithValue(
        Fragment$AccountDto(
          id: userId,
          username: 'person',
          permissions: const [Enum$UserPermission.MANAGE_SETTINGS],
          roles: const [],
        ),
      ),
      settledAccountAccessProvider.overrideWithValue(
        AccountAccess(capability: AccountCapability.unsupported),
      ),
      isWebProvider.overrideWithValue(web),
    ],
  );
  addTearDown(container.dispose);
  if (client != null) {
    await tester.runAsync(() async {
      await container.read(authCredentialsStoreProvider.future);
      await container.read(credentialsProvider.future);
    });
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: SignInSection()),
        ),
      ),
    ),
  );
  if (loading == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

void main() {
  for (final accounts in [false, true]) {
    for (final userId in [1, 2]) {
      for (final mode in [Enum$AuthMode.NONE, Enum$AuthMode.UI_LOGIN]) {
        testWidgets(
          'credential and UI rows: accounts $accounts, user $userId, $mode',
          (tester) async {
            await pumpSection(
              tester,
              accounts: accounts,
              userId: userId,
              mode: mode,
            );
            final admin =
                !accounts || userId == 1 || mode != Enum$AuthMode.UI_LOGIN;
            expect(
              find.text(accounts ? 'Admin username' : 'Username'),
              admin ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(accounts ? 'Admin password' : 'Password'),
              admin ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('JWT audience claim'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('Access token expiry'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('Stay signed in for'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            if (admin) {
              expect(find.text('secret'), findsNothing);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('missing fields hide the section', (tester) async {
    await pumpSection(tester, absent: true);
    expect(find.text('Authentication mode'), findsNothing);
  });
  testWidgets('None stays selectable with blank credentials', (tester) async {
    await pumpSection(tester, blank: true);
    await tester.tap(find.text('Authentication mode'));
    await tester.pumpAndSettle();
    final radios = tester.widgetList<RadioListTile>(
      find.byWidgetPredicate((widget) => widget is RadioListTile),
    );
    expect(radios.first.enabled, isTrue);
    expect(radios.skip(1).every((row) => row.enabled == false), isTrue);
  });
  for (final mode in [Enum$AuthMode.BASIC_AUTH, Enum$AuthMode.SIMPLE_LOGIN]) {
    testWidgets('web keeps current $mode visible and permits escape', (
      tester,
    ) async {
      await pumpSection(tester, web: true, mode: mode);
      await tester.tap(find.text('Authentication mode'));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<RadioListTile>(
            find.byWidgetPredicate((widget) => widget is RadioListTile),
          )
          .toList();
      expect(rows, hasLength(4));
      expect(rows[0].enabled, isTrue);
      expect(rows[1].enabled, isFalse);
      expect(rows[2].enabled, isFalse);
      expect(rows[3].enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unknown account capability offers retry', (tester) async {
    await pumpSection(tester, capabilityUnknown: true);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Authentication mode'), findsOneWidget);
  });
  testWidgets('loading then settings error can be retried', (tester) async {
    final loading = Completer<void>();
    await pumpSection(tester, loading: loading, settingsError: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loading.complete();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authentication mode'), findsOneWidget);
  });
  testWidgets('password editor reveals and saves only after confirmation', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    final client = GraphQLClient(
      cache: GraphQLCache(),
      link: Link.function((request, [forward]) async* {
        writes.add(request.variables);
        yield Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'setSettings': {
              '__typename': 'SetSettingsPayload',
              'settings': {
                '__typename': 'SettingsType',
                'authMode': 'UI_LOGIN',
                'authUsername': 'admin',
                'authPassword': 'changed',
                'jwtAudience': 'suwayomi',
                'jwtTokenExpiry': 'PT5M',
                'jwtRefreshExpiry': 'PT1440H',
              },
            },
          },
        );
      }),
    );
    final container = await pumpSection(tester, client: client);
    final store = container.read(authCredentialsStoreProvider.notifier);
    await tester.runAsync(
      () =>
          store.saveUiLoginTokens(accessToken: 'old', refreshToken: 'refresh'),
    );
    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility_rounded));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Change sign-in settings?'), findsOneWidget);
    expect(writes, isEmpty);
    await tester.tap(find.text('Change'));
    for (
      var i = 0;
      i < 100 && find.byType(TextField).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    expect(writes.single['settings'], {'authPassword': 'changed'});
    expect(store.uiLoginTokens()?.accessToken, 'old');
    expect(find.text('Change sign-in settings?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('server duration values round trip in minutes and days', () {
    expect(signInDuration('PT5M').inMinutes, 5);
    expect(signInDuration('PT1440H').inDays, 60);
    expect(signInDuration('P60D'), signInDuration('PT1440H'));
    expect(
      signInDuration('PT1H30M0.5S'),
      const Duration(hours: 1, minutes: 30, milliseconds: 500),
    );
    for (final value in [1, 5, 240]) {
      expect(signInDuration('PT${value}M').inMinutes, value);
    }
    for (final value in [1, 60, 365]) {
      expect(signInDuration('PT${value * 24}H').inDays, value);
    }
  });
}
