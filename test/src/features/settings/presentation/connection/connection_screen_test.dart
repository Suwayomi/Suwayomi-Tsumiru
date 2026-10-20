import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Map<String, Object> prefs, {
    bool isWeb = false,
  }) async {
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
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          if (isWeb) isWebProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the server address sections and LAN status', (
    tester,
  ) async {
    await pumpScreen(tester, const {});
    expect(find.text('Connection'), findsWidgets);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Add a local network address'), findsOneWidget);
    expect(find.text('Active connection'), findsNothing);

    // Once a LAN address is set, its row and the active connection appear.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScreen(tester, {
      DBKeys.serverExternalUrl.name: 'https://example.com',
      DBKeys.serverLanUrl.name: 'http://192.168.1.100:4567',
    });
    expect(find.text('Internal / LAN URL'), findsOneWidget);
    expect(find.text('Add a local network address'), findsNothing);
    expect(find.text('Active connection'), findsOneWidget);

    // A saved sign-in method the browser no longer offers still renders.
    for (final auth in [AuthType.basic, AuthType.simpleLogin]) {
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterSecureStorage.setMockInitialValues({});
      await pumpScreen(tester, {DBKeys.authType.name: auth.index}, isWeb: true);
      await tester.pumpAndSettle();
      expect(find.text('Authentication'), findsOneWidget, reason: '$auth');
      expect(tester.takeException(), isNull, reason: '$auth');
    }
  });

  final warning = find.textContaining('unencrypted http://');

  testWidgets('cleartext warning shows for a remote http:// address with '
      'sign-in', (tester) async {
    await pumpScreen(tester, {
      DBKeys.serverExternalUrl.name: 'http://suwayomi.example.net',
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    expect(warning, findsOneWidget);
  });

  testWidgets('cleartext warning stays hidden otherwise', (tester) async {
    // https external with a LAN http address has nothing to leak remotely.
    await pumpScreen(tester, {
      DBKeys.serverExternalUrl.name: 'https://suwayomi.example.net',
      DBKeys.serverLanUrl.name: 'http://192.168.1.100:4567',
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    expect(warning, findsNothing);

    // No sign-in, nothing to leak.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScreen(tester, {
      DBKeys.serverExternalUrl.name: 'http://suwayomi.example.net',
      DBKeys.authType.name: AuthType.none.index,
    });
    expect(warning, findsNothing);
  });
}
