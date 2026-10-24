import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_stub.dart'
    as pending;
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

import 'data/recorded_auth_response.dart';

void main() {
  for (final succeeds in [false, true]) {
    testWidgets(
      'recovery verifies None before replacing credentials: $succeeds',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({
          DBKeys.authType.name: AuthType.basic.index,
        });
        final container = ProviderContainer(
          overrides: [
            pendingTrackerOAuthStoreProvider.overrideWithValue(
              pending.createPendingTrackerOAuthStore(),
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            unauthenticatedGraphQlClientProvider.overrideWithValue(
              recordedAuthClient(
                succeeds ? 200 : 401,
                succeeds
                    ? '{"data":{"__typename":"Query","settings":{"__typename":"SettingsType","authMode":"NONE","jwtAudience":"server"}}}'
                    : 'Unauthorized',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        late AuthCredentialsStore store;
        await tester.runAsync(() async {
          await container.read(authCredentialsStoreProvider.future);
          store = container.read(authCredentialsStoreProvider.notifier);
          await container.read(credentialsProvider.future);
          await container.read(credentialsProvider.notifier).set('Basic old');
          await store.saveUiLoginTokens(
            accessToken: 'old',
            refreshToken: 'refresh',
          );
        });
        container.read(needsReauthProvider.notifier).set(true);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: LoginCredentialsPopup(
                  authType: AuthType.basic,
                  allowModeSelection: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Authentication mode'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
        await tester.pumpAndSettle();
        for (final label in [
          'None',
          'Basic authentication',
          'Simple login',
          'UI login',
        ]) {
          expect(find.text(label), findsWidgets);
        }
        await tester.tap(find.text('None').last);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          for (var i = 0; i < 100 && (i == 0 || store.identityChanging); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(
          container.read(authTypeKeyProvider),
          succeeds ? AuthType.none : AuthType.basic,
        );
        expect(
          container.read(credentialsProvider).value,
          succeeds ? isNull : 'Basic old',
        );
        expect(store.uiLoginTokens()?.accessToken, succeeds ? isNull : 'old');
        expect(container.read(needsReauthProvider), !succeeds);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('web recovery offers only None and UI login as destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingTrackerOAuthStoreProvider.overrideWithValue(
            pending.createPendingTrackerOAuthStore(),
          ),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          isWebProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LoginCredentialsPopup(
              authType: AuthType.basic,
              allowModeSelection: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UI login').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
}
