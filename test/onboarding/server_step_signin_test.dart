// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Widget test for the gated-server flow: Test connection → "needs a login" →
// auth sub-form.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/presentation/account_code_dialog.dart';
import 'package:tsumiru/src/features/account/presentation/account_session_host.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

const _aboutOk =
    '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"2.0"}}}';
const _authUnauthorized = '{"data":null,"errors":[{"message":"Unauthorized"}]}';

/// A server that confirms via aboutServer but gates the @RequireAuth probe →
/// Test connection should report "needs a login" and reveal the auth sub-form.
http.Client _gatedServerClient() => MockClient.streaming((request, body) async {
  final q =
      ((jsonDecode(await body.bytesToString()) as Map)['query'] as String);
  final isAbout = q.contains('aboutServer');
  return http.StreamedResponse(
    Stream.value(utf8.encode(isAbout ? _aboutOk : _authUnauthorized)),
    200,
  );
});

class _SimpleLoginCoordinator extends AuthCoordinator {
  @override
  Future<String> verifySimpleCredentials({
    required String serverBaseUrl,
    required String username,
    required String password,
  }) async {
    if (password != 'correct') throw StateError('Rejected');
    return 'verified-session';
  }
}

void main() {
  for (final needsLogin in [true, false]) {
    testWidgets(
      'connection result survives the app session restart (login: $needsLogin)',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({'onboarding.step': 1});
        final preferences = await SharedPreferences.getInstance();
        await tester.binding.setSurfaceSize(const Size(1080, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Future<ProviderContainer> createContainer() async {
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              onboardingHttpClientProvider.overrideWithValue(
                () => MockClient.streaming((request, body) async {
                  final query =
                      (jsonDecode(await body.bytesToString()) as Map)['query']
                          as String;
                  return http.StreamedResponse(
                    Stream.value(
                      utf8.encode(
                        query.contains('aboutServer')
                            ? _aboutOk
                            : needsLogin
                            ? _authUnauthorized
                            : '{"data":{"downloadStatus":{"state":"STOPPED"}}}',
                      ),
                    ),
                    200,
                  );
                }),
              ),
            ],
          );
          await container.read(authCredentialsStoreProvider.future);
          return container;
        }

        var restarts = 0;
        await tester.pumpWidget(
          AccountSessionHost(
            initialContainer: await createContainer(),
            sessionKey: (c) => c.read(currentServerAddressProvider),
            restart: (_) async {
              restarts++;
              return createContainer();
            },
            builder: (changing) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Offstage(
                offstage: changing,
                child: const OnboardingScreen(),
              ),
            ),
            loading: const SizedBox(),
            errorBuilder: (error) => Text('$error'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Server URL'),
          'http://server:4567',
        );
        await tester.tap(find.text('Test connection'));
        await tester.pumpAndSettle();
        expect(restarts, greaterThan(0));
        expect(
          find.text(
            needsLogin
                ? 'This server needs a login'
                : 'Connected — Suwayomi v2.0',
          ),
          findsOneWidget,
        );
        expect(preferences.getString('onboarding.pendingProbe'), '');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final password in ['correct', 'wrong']) {
    testWidgets(
      'Simple Login with $password password completes only on success',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({
          'onboarding.step': 1,
          'onboarding.pendingProbe': 'http://server',
        });
        final preferences = await SharedPreferences.getInstance();
        await tester.binding.setSurfaceSize(const Size(1080, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = GoRouter(
          initialLocation: '/onboarding',
          routes: [
            GoRoute(
              path: '/onboarding',
              builder: (_, _) => const OnboardingScreen(),
            ),
            GoRoute(
              path: '/library/:categoryId',
              builder: (_, _) => const Scaffold(body: Text('Library')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              onboardingHttpClientProvider.overrideWithValue(
                _gatedServerClient,
              ),
              authCoordinatorProvider.overrideWith(_SimpleLoginCoordinator.new),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester
            .widget<DropdownMenu<AuthType>>(find.byType(DropdownMenu<AuthType>))
            .onSelected!(AuthType.simpleLogin);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'User Name'),
          'reader',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          password,
        );
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        if (password == 'correct') {
          expect(find.text('Library'), findsNothing);
          expect(find.text("You're all set"), findsOneWidget);
          expect(
            preferences.getBool(DBKeys.onboardingComplete.name),
            isNot(true),
          );
          await tester.tap(find.text('Finish'));
          await tester.pumpAndSettle();
          expect(find.text('Library'), findsOneWidget);
          expect(preferences.getBool(DBKeys.onboardingComplete.name), isTrue);
        } else {
          expect(find.text('Library'), findsNothing);
          expect(
            find.textContaining("Those credentials didn't work"),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, 'User Name'))
                .controller!
                .text,
            'reader',
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, 'Password'))
                .controller!
                .text,
            password,
          );
          expect(
            preferences.getBool(DBKeys.onboardingComplete.name),
            isNot(true),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('interrupted probe resumes and exposes UI account forms', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'onboarding.step': 1,
      'onboarding.pendingProbe': '192.168.0.10',
      DBKeys.serverExternalUrl.name: 'http://192.168.0.10:4567',
      DBKeys.serverUrl.name: 'http://192.168.0.10:4567',
      DBKeys.serverPortToggle.name: false,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          onboardingHttpClientProvider.overrideWithValue(_gatedServerClient),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This server needs a login'), findsOneWidget);
    expect(preferences.getString('onboarding.pendingProbe'), '');
    final menu = tester.widget<DropdownMenu<AuthType>>(
      find.byType(DropdownMenu<AuthType>),
    );
    menu.onSelected!(AuthType.uiLogin);
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AccountCodeDialog>(find.byType(AccountCodeDialog)).mode,
      AccountCodeMode.registration,
    );
  });

  testWidgets('Test connection on a gated server reveals the auth sub-form', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();

    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          onboardingHttpClientProvider.overrideWithValue(_gatedServerClient),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1 → Step 2.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your server'), findsOneWidget);
    // The two distinct actions exist.
    expect(find.text('Search my network'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);

    // Type an address and test it.
    await tester.enterText(find.byType(TextField).first, '192.168.0.10');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    // Gated → "needs a login" + the auth dropdown (Basic default) + creds.
    expect(find.text('This server needs a login'), findsOneWidget);
    expect(find.text('Basic auth'), findsWidgets);
    expect(find.widgetWithText(TextField, 'User Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('wrong auth type / credentials must NOT report connected — they are '
      'rejected and Next stays gated', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();

    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          // Gated server: aboutServer answers, but the @RequireAuth probe is
          // ALWAYS Unauthorized — no credential of any kind authorises it. This
          // models picking the wrong auth type (e.g. Basic on a ui_login
          // server, whose public aboutServer answers regardless of creds).
          onboardingHttpClientProvider.overrideWithValue(_gatedServerClient),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '192.168.0.10');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('This server needs a login'), findsOneWidget);

    // Enter credentials with the default (Basic) auth type and Sign in.
    await tester.enterText(
      find.widgetWithText(TextField, 'User Name'),
      'whoever',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'whatever',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The credentials are rejected — NOT a false "Connected".
    expect(
      find.text(
        "Those credentials didn't work. Double-check your "
        'username, password, and sign-in method.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Connected'), findsNothing);

    // Next is still gated (onboarding can't be finished with a broken config).
    final nextButton = tester.widget<BrandButton>(
      find.widgetWithText(BrandButton, 'Next'),
    );
    expect(
      nextButton.onPressed,
      isNull,
      reason: 'Next must stay disabled when sign-in was rejected',
    );
  });
}
