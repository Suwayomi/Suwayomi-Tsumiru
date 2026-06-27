import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/presentation/settings/tracking_settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('TrackingSettingsScreen shows both toggles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        trackersProvider.overrideWith((ref) async => []),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TrackingSettingsScreen(),
      ),
    ));
    await tester.pump();
    expect(find.text('Update progress after reading'), findsOneWidget);
  });
}
