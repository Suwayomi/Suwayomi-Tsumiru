import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('ConnectionScreen shows the Server address section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.text('Connection'), findsWidgets);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Add a local network address'), findsOneWidget);
    expect(find.text('Active connection'), findsNothing);
  });

  testWidgets('ConnectionScreen shows LAN status after a LAN address is set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      DBKeys.serverExternalUrl.name: 'https://example.com',
      DBKeys.serverLanUrl.name: 'http://192.168.1.100:4567',
    });
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

    expect(find.text('Internal / LAN URL'), findsOneWidget);
    expect(find.text('Add a local network address'), findsNothing);
    expect(find.text('Active connection'), findsOneWidget);
  });

  group('cleartext warning', () {
    Future<void> pumpWith(WidgetTester tester, Map<String, Object> prefs) async {
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

    final warning = find.textContaining('unencrypted http://');

    testWidgets('shows for a remote http:// address with sign-in', (
      tester,
    ) async {
      await pumpWith(tester, {
        DBKeys.serverExternalUrl.name: 'http://suwayomi.example.net',
        DBKeys.authType.name: AuthType.uiLogin.index,
      });
      expect(warning, findsOneWidget);
    });

    testWidgets('stays hidden for https:// with a LAN http:// address', (
      tester,
    ) async {
      await pumpWith(tester, {
        DBKeys.serverExternalUrl.name: 'https://suwayomi.example.net',
        DBKeys.serverLanUrl.name: 'http://192.168.1.100:4567',
        DBKeys.authType.name: AuthType.uiLogin.index,
      });
      expect(warning, findsNothing);
    });

    testWidgets('stays hidden without sign-in: there is nothing to leak', (
      tester,
    ) async {
      await pumpWith(tester, {
        DBKeys.serverExternalUrl.name: 'http://suwayomi.example.net',
        DBKeys.authType.name: AuthType.none.index,
      });
      expect(warning, findsNothing);
    });
  });
}
