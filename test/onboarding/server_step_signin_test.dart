// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Widget test for the gated-server flow: Test connection → "needs a login" →
// auth sub-form.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/presentation/account_session_host.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

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

/// A UI-login server: aboutServer answers, the @RequireAuth probe is
/// Unauthorized, and GET / serves the app shell (200) rather than bouncing to
/// /login.html — the shape detection reads as [AuthType.uiLogin].
http.Client _uiLoginServerClient() =>
    MockClient.streaming((request, body) async {
      if (request.method == 'GET') {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
      }
      final q =
          ((jsonDecode(await body.bytesToString()) as Map)['query'] as String);
      final isAbout = q.contains('aboutServer');
      return http.StreamedResponse(
        Stream.value(utf8.encode(isAbout ? _aboutOk : _authUnauthorized)),
        200,
      );
    });

class _LoginCoordinator extends AuthCoordinator {
  @override
  void build() {}

  @override
  Future<void> loginUi({
    required GraphQLClient gqlClient,
    required String username,
    required String password,
    String? serverBaseUrl,
  }) async {
    expect(serverBaseUrl, 'http://192.168.2.4:4568');
    expect(ref.read(currentServerAddressProvider), serverBaseUrl);
    if (password != 'password') {
      throw OperationException(
        graphqlErrors: [const GraphQLError(message: 'Unauthorized')],
      );
    }
    await ref
        .read(authCredentialsStoreProvider.notifier)
        .saveUiLoginTokens(accessToken: 'access', refreshToken: 'refresh');
  }
}

void main() {
  for (final isWeb in [false, true]) {
    for (final needsLogin in [false, true]) {
      testWidgets(
        '${isWeb ? 'web' : 'native'} probe stays mounted and runs once '
        'before ${needsLogin ? 'sign-in' : 'Next'} adopts the server',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          SharedPreferences.setMockInitialValues({'onboarding.step': 1});
          final sp = await SharedPreferences.getInstance();
          await tester.binding.setSurfaceSize(const Size(1080, 2400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final aboutReady = Completer<void>();
          final authReady = Completer<void>();
          var aboutCalls = 0;
          var authCalls = 0;
          var loginCalls = 0;
          var restarts = 0;
          ProviderContainer createContainer() => ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(sp),
              isWebProvider.overrideWithValue(isWeb),
              authCoordinatorProvider.overrideWith(_LoginCoordinator.new),
              onboardingHttpClientProvider.overrideWithValue(
                () => MockClient.streaming((request, body) async {
                  expect(request.url.host, '192.168.2.4');
                  expect(request.url.port, 4568);
                  if (request.method == 'GET') {
                    return http.StreamedResponse(
                      const Stream<List<int>>.empty(),
                      200,
                    );
                  }
                  final payload = jsonDecode(await body.bytesToString()) as Map;
                  final query = payload['query'] as String;
                  if (query.contains('mutation Login')) {
                    loginCalls++;
                    expect(payload['variables']['input']['username'], 'reader');
                    final rejected =
                        payload['variables']['input']['password'] != 'password';
                    return http.StreamedResponse(
                      Stream.value(
                        utf8.encode(
                          rejected
                              ? _authUnauthorized
                              : '{"data":{"__typename":"Mutation","login":{'
                                    '"__typename":"LoginPayload",'
                                    '"accessToken":"access",'
                                    '"refreshToken":"refresh"}}}',
                        ),
                      ),
                      200,
                      headers: {'content-type': 'application/json'},
                    );
                  }
                  final isAbout = query.contains('aboutServer');
                  if (isAbout) {
                    aboutCalls++;
                    await aboutReady.future;
                  } else {
                    authCalls++;
                    await authReady.future;
                  }
                  return http.StreamedResponse(
                    Stream.value(
                      utf8.encode(
                        isAbout
                            ? _aboutOk
                            : needsLogin
                            ? _authUnauthorized
                            : '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}',
                      ),
                    ),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              ),
            ],
          );
          var active = createContainer();
          await active.read(authCredentialsStoreProvider.future);
          active.read(authCredentialsStoreProvider.notifier).activateSession();
          final originalAddress = active.read(currentServerAddressProvider);
          final originalEpoch = active
              .read(authCredentialsStoreProvider)
              .value!
              .sessionEpoch;
          await tester.pumpWidget(
            AccountSessionHost(
              initialContainer: active,
              sessionKey: (container) => (
                container.read(currentServerAddressProvider),
                container
                    .read(authCredentialsStoreProvider)
                    .value
                    ?.uiAccessToken,
              ),
              restart: (previous) async {
                restarts++;
                active = createContainer();
                await active.read(authCredentialsStoreProvider.future);
                active
                    .read(authCredentialsStoreProvider.notifier)
                    .activateSession();
                return active;
              },
              builder: (changing) => MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Offstage(
                  offstage: changing,
                  child: const OnboardingScreen(),
                ),
              ),
              loading: const Text(
                'Session loading',
                textDirection: TextDirection.ltr,
              ),
              errorBuilder: (error) =>
                  Text('$error', textDirection: TextDirection.ltr),
            ),
          );
          await tester.pumpAndSettle();
          final field = find.widgetWithText(TextField, 'Server URL');
          final element = tester.element(field);
          await tester.enterText(field, 'http://192.168.2.4:4568');
          await tester.tap(find.text('Test connection'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(aboutCalls, 1);
          expect(find.text('Checking connection…'), findsWidgets);
          expect(tester.element(field), same(element));
          aboutReady.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(authCalls, 1);
          expect(find.text('Checking connection…'), findsWidgets);
          expect(tester.element(field), same(element));
          authReady.complete();
          await tester.pumpAndSettle();
          expect(aboutCalls, 1);
          expect(authCalls, 1);
          expect(restarts, 0);
          expect(tester.element(field), same(element));
          expect(find.text('Session loading'), findsNothing);
          expect(
            active.read(authCredentialsStoreProvider).value!.sessionEpoch,
            originalEpoch,
          );
          expect(active.read(currentServerAddressProvider), originalAddress);
          expect(sp.getString('onboarding.pendingProbe'), '');
          if (needsLogin) {
            expect(find.text('This server needs a login'), findsOneWidget);
            await tester.enterText(
              find.widgetWithText(TextField, 'User Name'),
              'reader',
            );
            await tester.enterText(
              find.widgetWithText(TextField, 'Password'),
              'Password',
            );
            await tester.tap(find.text('Sign in'));
            await tester.pumpAndSettle();
            expect(loginCalls, 1);
            expect(restarts, 0);
            expect(active.read(currentServerAddressProvider), originalAddress);
            expect(
              active.read(authCredentialsStoreProvider).value!.sessionEpoch,
              originalEpoch,
            );
            expect(tester.element(field), same(element));
            expect(
              tester.widget<TextField>(field).controller!.text,
              'http://192.168.2.4:4568',
            );
            expect(
              tester
                  .widget<TextField>(find.widgetWithText(TextField, 'User Name'))
                  .controller!
                  .text,
              'reader',
            );
            expect(find.text('This server needs a login'), findsOneWidget);
            expect(
              find.textContaining("Those credentials didn't work"),
              findsOneWidget,
            );
            expect(find.text("You're all set"), findsNothing);
            await tester.enterText(
              find.widgetWithText(TextField, 'Password'),
              'password',
            );
            await tester.tap(find.text('Sign in'));
          } else {
            expect(find.textContaining('Connected'), findsOneWidget);
            await tester.tap(find.text('Next'));
          }
          await tester.pumpAndSettle();
          expect(restarts, 1);
          expect(
            active.read(serverExternalUrlProvider),
            'http://192.168.2.4:4568',
          );
          expect(
            active.read(currentServerAddressProvider),
            'http://192.168.2.4:4568',
          );
          expect(sp.getInt('onboarding.step'), 2);
          expect(find.text("You're all set"), findsOneWidget);
          expect(aboutCalls, 1);
          expect(authCalls, 1);
          expect(loginCalls, needsLogin ? 2 : 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  /// Pumps the onboarding wizard on step 2 with [client] standing in for the
  /// server, then runs "Test connection" on [address].
  Future<void> pumpAndTestConnection(
    WidgetTester tester,
    http.Client Function() client, {
    String address = '192.168.0.10',
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          onboardingHttpClientProvider.overrideWithValue(client),
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
    await tester.enterText(find.byType(TextField).first, address);
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
  }

  testWidgets('a UI-login server pre-selects UI login with no user tap', (
    tester,
  ) async {
    await pumpAndTestConnection(tester, _uiLoginServerClient);

    expect(find.text('This server needs a login'), findsOneWidget);
    expect(find.text('UI login'), findsWidgets);
    expect(
      tester
          .widget<DropdownMenu<AuthType>>(find.byType(DropdownMenu<AuthType>))
          .initialSelection,
      AuthType.uiLogin,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wrong auth type / credentials must NOT report connected — they are '
    'rejected and Next cannot finish',
    (tester) async {
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

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text("You're all set"), findsNothing);
      expect(
        find.textContaining("Those credentials didn't work"),
        findsOneWidget,
      );
    },
  );
}
