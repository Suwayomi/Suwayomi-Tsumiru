import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_actions.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/presentation/account_code_dialog.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_status.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/inline_auth_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/authentication/authentication_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _Actions extends AccountActions {
  _Actions(super.ref);
  final submissions = <List<String?>>[];
  int signOutCalls = 0;
  @override
  Future<void> redeemCode({
    required String code,
    String? username,
    required String password,
  }) async {
    submissions.add([code, username, password]);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

void main() {
  late SharedPreferences preferences;
  late _Actions actions;
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    AccountCapability capability = AccountCapability.unknown,
    bool stored = false,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: capability),
          ),
          hasStoredCredentialsProvider.overrideWithValue(stored),
          accountActionsProvider.overrideWith((ref) => actions = _Actions(ref)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final popup in [false, true]) {
    testWidgets('UI login reaches recovery and registration, popup=$popup', (
      tester,
    ) async {
      await mount(
        tester,
        popup
            ? const LoginCredentialsPopup(authType: AuthType.uiLogin)
            : const InlineAuthSection(),
      );
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AccountCodeDialog>(
        find.byType(AccountCodeDialog),
      );
      expect(dialog.mode, AccountCodeMode.recovery);
      await dialog.onSubmit(code: 'code', password: 'password');
      expect(actions.submissions, [
        ['code', null, 'password'],
      ]);
    });

    testWidgets('known unsupported server hides code links, popup=$popup', (
      tester,
    ) async {
      await mount(
        tester,
        popup
            ? const LoginCredentialsPopup(authType: AuthType.uiLogin)
            : const InlineAuthSection(),
        capability: AccountCapability.unsupported,
      );
      expect(find.text('Create account'), findsNothing);
      expect(find.text('Reset password'), findsNothing);
    });
  }

  testWidgets('inline without stored credentials displays sign-in form', (
    tester,
  ) async {
    await mount(tester, const InlineAuthSection());
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
  });

  for (final inline in [false, true]) {
    testWidgets(
      'logout calls shared action and preserves UI mode, inline=$inline',
      (tester) async {
        await mount(
          tester,
          inline ? const InlineAuthSection() : const AuthenticationSection(),
          stored: true,
        );
        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Log out'));
        await tester.pumpAndSettle();
        expect(actions.signOutCalls, 1);
        expect(
          preferences.getInt(DBKeys.authType.name),
          AuthType.uiLogin.index,
        );
      },
    );
  }
}
