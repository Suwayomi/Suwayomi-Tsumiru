// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Widget test for the gated-server flow: Test connection → "needs a login" →
// auth sub-form.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

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

void main() {
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
