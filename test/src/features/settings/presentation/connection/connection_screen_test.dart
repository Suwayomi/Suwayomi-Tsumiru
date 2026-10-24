import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/inline_auth_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    // Phone surface: the page keeps its own AppBar here (desktop draws the
    // toolbar in the shell bar instead); the sections below are
    // layout-independent.
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'selecting a protected mode opens sign-in without committing it',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        DBKeys.authType.name: AuthType.none.index,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ConnectionAuthTypeTile()),
          ),
        ),
      );
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UI Login (recommended)'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginCredentialsPopup), findsOneWidget);
      expect(prefs.getInt(DBKeys.authType.name), AuthType.none.index);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(prefs.getInt(DBKeys.authType.name), AuthType.none.index);
    },
  );

  final warning = find.textContaining('unencrypted http://');

  testWidgets('cleartext warning shows for a remote http:// address with '
      'sign-in', (tester) async {
    await pumpScreen(tester, {
      DBKeys.serverExternalUrl.name: 'http://suwayomi.example.net',
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    expect(warning, findsOneWidget);
  });
}
