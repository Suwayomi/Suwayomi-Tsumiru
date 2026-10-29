import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/main.dart' as app;
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/data/macos_app_updater.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

const _channel = MethodChannel('tsumiru/sparkle_updater');

const play = bool.fromEnvironment('TSUMIRU_GOOGLE_PLAY');

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Tsumiru',
  packageName: 'test',
  version: '1.0.0',
  buildNumber: '1',
);

GraphQLClient _emptyClient() => GraphQLClient(
  link: Link.function((request, [forward]) => const Stream.empty()),
  cache: GraphQLCache(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int initializeCalls;
  late bool nativeInitializeResult;

  setUp(() {
    initializeCalls = 0;
    nativeInitializeResult = true;
    debugMacOSOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'initialize' => () {
              initializeCalls++;
              return nativeInitializeResult;
            }(),
            'checkForUpdates' => true,
            _ => throw MissingPluginException(),
          };
        });
    addTearDown(() {
      debugMacOSOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
  });

  Future<SharedPreferences> loadPrefs() async {
    SharedPreferences.setMockInitialValues(const {});
    return SharedPreferences.getInstance();
  }

  /// Mirrors `restartSession`: the next container takes the updater from the
  /// previous one through the production session factory.
  ProviderContainer restartContainer(
    ProviderContainer previous,
    PackageInfo packageInfo,
    SharedPreferences prefs,
  ) => app.createSessionContainerForTest(
    packageInfo: packageInfo,
    preferences: prefs,
    macOSUpdater: previous.read(macOSAppUpdaterProvider),
  );

  /// Reads update routing through a child container so the session factory
  /// itself stays exactly as production builds it.
  ProviderContainer routingChild(ProviderContainer session) {
    final child = ProviderContainer(
      parent: session,
      overrides: [
        graphQlClientProvider.overrideWithValue(_emptyClient()),
        serverHostedWebProvider.overrideWithValue(false),
      ],
    );
    addTearDown(child.dispose);
    return child;
  }

  Future<int> githubCalls(ProviderContainer session) async {
    var calls = 0;
    final result = await http.runWithClient(
      routingChild(session).read(aboutRepositoryProvider).checkUpdate,
      () => MockClient((request) async {
        calls++;
        return http.Response('{"tag_name":"v9.0.0"}', 200);
      }),
    );
    expect(result.hasError, isFalse);
    return calls;
  }

  test(
    'restart keeps the initialized updater and native routing without re-init',
    () async {
      final prefs = await loadPrefs();
      final packageInfo = _packageInfo();

      // _startApp: one app-lifetime updater, initialized once.
      final updater = MacOSAppUpdater();
      expect(await updater.initialize(), isTrue);
      expect(initializeCalls, 1);

      final old = app.createSessionContainerForTest(
        packageInfo: packageInfo,
        preferences: prefs,
        macOSUpdater: updater,
      );
      expect(old.read(macOSAppUpdaterProvider), same(updater));
      expect(old.read(macOSAppUpdaterProvider).isAvailable, isTrue);
      expect(await githubCalls(old), 0);

      final next = restartContainer(old, packageInfo, prefs);
      addTearDown(next.dispose);
      old.dispose();

      // Same instance survives disposal; native init is not repeated.
      expect(next.read(macOSAppUpdaterProvider), same(updater));
      expect(next.read(macOSAppUpdaterProvider).isAvailable, isTrue);
      expect(initializeCalls, 1);
      expect(await githubCalls(next), 0);
      expect(
        await next.read(macOSAppUpdaterProvider).checkForUpdates(),
        isTrue,
      );
      expect(next.read(macOSAppUpdaterProvider).isAvailable, isTrue);
    },
  );

  test('restart keeps a failed native updater on the GitHub fallback', () async {
    nativeInitializeResult = false;
    final prefs = await loadPrefs();
    final packageInfo = _packageInfo();

    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);

    final old = app.createSessionContainerForTest(
      packageInfo: packageInfo,
      preferences: prefs,
      macOSUpdater: updater,
    );
    expect(old.read(macOSAppUpdaterProvider).isAvailable, isFalse);

    final next = restartContainer(old, packageInfo, prefs);
    addTearDown(next.dispose);
    old.dispose();

    expect(next.read(macOSAppUpdaterProvider), same(updater));
    expect(next.read(macOSAppUpdaterProvider).isAvailable, isFalse);
    expect(initializeCalls, 1);
    // Unavailable: manual checks never touch the native channel.
    expect(await next.read(macOSAppUpdaterProvider).checkForUpdates(), isFalse);
    // The repository falls through to GitHub on the restarted container.
    expect(await githubCalls(next), play ? 0 : 1);
  });
}
