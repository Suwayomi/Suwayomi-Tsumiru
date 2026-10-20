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
