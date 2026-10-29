import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/data/macos_app_updater.dart';
import 'package:tsumiru/src/features/about/presentation/about/about_screen.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

const _channel = MethodChannel('tsumiru/sparkle_updater');

const play = bool.fromEnvironment('TSUMIRU_GOOGLE_PLAY');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool nativeCheckResult;

  setUp(() {
    nativeCheckResult = true;
    debugMacOSOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'initialize' => true,
            'checkForUpdates' => nativeCheckResult,
            _ => throw MissingPluginException(),
          };
        });
    addTearDown(() {
      debugMacOSOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
  });

  Future<int> tapCheckForUpdates(WidgetTester tester) async {
    var calls = 0;
    await http.runWithClient(
      () async {
        // Production always watches aboutProvider while About is open, which
        // subscribes the repository; hold the same subscription across the
        // tap's async gap since aboutProvider is stubbed out here.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AboutScreen)),
        );
        final subscription = container.listen(
          aboutRepositoryProvider,
          (_, _) {},
        );
        try {
          final label = AppLocalizations.of(
            tester.element(find.byType(AboutScreen)),
          )!.checkForUpdates;
          final tile = find.text(label);
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
        } finally {
          subscription.close();
        }
      },
      () => MockClient((request) async {
        calls++;
        return http.Response('{"tag_name":"v9.0.0"}', 200);
      }),
    );
    return calls;
  }

  Future<void> pumpAbout(
    WidgetTester tester,
    MacOSAppUpdater updater,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWithValue(
            PackageInfo(
              appName: 'Tsumiru',
              packageName: 'test',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWithValue(
            GraphQLClient(
              link: Link.function(
                (request, [forward]) => const Stream.empty(),
              ),
              cache: GraphQLCache(),
            ),
          ),
          aboutProvider.overrideWith((ref) async => null),
          aboutWebUIProvider.overrideWith((ref) async => null),
          serverHostedWebProvider.overrideWithValue(false),
          macOSAppUpdaterProvider.overrideWithValue(updater),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'native-handled tap never reaches GitHub',
    (tester) async {
      nativeCheckResult = true;
      final updater = MacOSAppUpdater();
      expect(await updater.initialize(), isTrue);
      await pumpAbout(tester, updater);

      expect(await tapCheckForUpdates(tester), 0);
      expect(updater.isAvailable, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    },
    skip: play,
  );

  testWidgets(
    'native false demotes and falls through to GitHub on the same tap',
    (tester) async {
      nativeCheckResult = false;
      final updater = MacOSAppUpdater();
      expect(await updater.initialize(), isTrue);
      await pumpAbout(tester, updater);

      expect(await tapCheckForUpdates(tester), 1);
      expect(updater.isAvailable, isFalse);
      expect(find.textContaining('v9.0.0'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
    skip: play,
  );

  testWidgets(
    'Play hides the client update entry',
    (tester) async {
      final updater = MacOSAppUpdater();
      expect(await updater.initialize(), isTrue);
      await pumpAbout(tester, updater);

      final label = AppLocalizations.of(
        tester.element(find.byType(AboutScreen)),
      )!.checkForUpdates;
      expect(find.text(label), findsNothing);
    },
    skip: !play,
  );
}
