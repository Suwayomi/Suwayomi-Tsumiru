// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/account/presentation/account_session_host.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_sign_in.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  for (final rejected in [false, true]) {
    testWidgets(
      rejected
          ? 'rejection leaves onboarding unfinished'
          : 'final step survives replacement without completing onboarding',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({
          'onboarding.step': 1,
          'onboarding.pendingProbe': 'http://server',
        });
        final preferences = await SharedPreferences.getInstance();
        ProviderContainer create() => ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        );
        var active = create();
        addTearDown(() => active.dispose());
        await active.read(authCredentialsStoreProvider.future);
        var restarts = 0;
        await tester.pumpWidget(
          AccountSessionHost(
            initialContainer: active,
            sessionKey: (scope) =>
                scope
                    .read(authCredentialsStoreProvider)
                    .value
                    ?.simpleLoginCookie ??
                '',
            restart: (_) async {
              restarts++;
              expect(
                preferences.getBool(DBKeys.onboardingComplete.name),
                isNot(true),
              );
              expect(preferences.getInt('onboarding.step'), 2);
              expect(preferences.getString('onboarding.pendingProbe'), '');
              active = create();
              await active.read(authCredentialsStoreProvider.future);
              return active;
            },
            loading: const SizedBox(),
            errorBuilder: (error) =>
                Text('$error', textDirection: TextDirection.ltr),
            builder: (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  if (restarts > 0) {
                    return const OnboardingScreen();
                  }
                  return TextButton(
                    onPressed: () async {
                      try {
                        await finishOnboardingSignIn(ref, () async {
                          final store = ref.read(
                            authCredentialsStoreProvider.notifier,
                          );
                          await store.withIdentityChange(() async {
                            if (rejected) throw StateError('Rejected');
                            await store.saveSimpleLoginCookie(
                              'verified-session',
                            );
                          });
                        });
                      } catch (_) {}
                    },
                    child: const Text('Sign in'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(restarts, rejected ? 0 : 1);
        expect(
          find.text(rejected ? 'Sign in' : "You're all set"),
          findsOneWidget,
        );
        expect(
          preferences.getBool(DBKeys.onboardingComplete.name),
          isNot(true),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
