import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/data/macos_app_updater.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
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

AboutRepository _repository({bool Function()? isNativeUpdaterAvailable}) =>
    AboutRepository(
      client: _emptyClient(),
      packageInfo: _packageInfo(),
      isNativeUpdaterAvailable: isNativeUpdaterAvailable,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    addTearDown(() {
      debugMacOSOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });
  });

  Future<void> mockNative({required bool? initialize, bool? check}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'initialize' => initialize,
            'checkForUpdates' => check,
            _ => throw MissingPluginException(),
          };
        });
  }

  test('non-macOS builds never touch the native channel', () async {
    debugMacOSOverride = false;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls++;
          return true;
        });
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);
    expect(updater.isAvailable, isFalse);
    expect(await updater.checkForUpdates(), isFalse);
    expect(calls, 0);
  });

  test('startup initialization records native availability', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: true);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(macOSAppUpdaterProvider).initialize(), isTrue);
    expect(
      container.read(macOSAppUpdaterProvider).isAvailable,
      isTrue,
    );
  });

  test('startup initialization failure leaves the fallback in charge', () async {
    debugMacOSOverride = true;
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('unconfigured native updater reports unavailable', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: false);
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('null native result reports unavailable', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: null);
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('platform failure during initialization reports unavailable', () async {
    debugMacOSOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => throw PlatformException(code: 'error'),
        );
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('manual check is skipped while unavailable', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: false, check: true);
    final updater = MacOSAppUpdater();
    await updater.initialize();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls++;
          return true;
        });
    expect(await updater.checkForUpdates(), isFalse);
    expect(calls, 0);
  });

  test('manual check uses native UI when available', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: true, check: true);
    final updater = MacOSAppUpdater();
    await updater.initialize();
    expect(await updater.checkForUpdates(), isTrue);
    expect(updater.isAvailable, isTrue);
  });

  test('busy native updater stays available across repeated checks', () async {
    // Native true even while busy must not demote or open the GitHub flow.
    debugMacOSOverride = true;
    await mockNative(initialize: true, check: true);
    final updater = MacOSAppUpdater();
    await updater.initialize();
    expect(await updater.checkForUpdates(), isTrue);
    expect(await updater.checkForUpdates(), isTrue);
    expect(updater.isAvailable, isTrue);
  });

  test('missing native controller demotes the updater for fallback', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: true, check: false);
    final updater = MacOSAppUpdater();
    await updater.initialize();
    expect(await updater.checkForUpdates(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('failed native check demotes the updater for fallback', () async {
    debugMacOSOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'initialize' => true,
            'checkForUpdates' => throw PlatformException(code: 'busy'),
            _ => throw MissingPluginException(),
          };
        });
    final updater = MacOSAppUpdater();
    await updater.initialize();
    expect(await updater.checkForUpdates(), isFalse);
    expect(updater.isAvailable, isFalse);
  });

  test('repository skips GitHub when the native updater is available', () async {
    var calls = 0;
    final result = await http.runWithClient(
      _repository(isNativeUpdaterAvailable: () => true).checkUpdate,
      () => MockClient((request) async {
        calls++;
        return http.Response('{"tag_name":"v9.0.0"}', 200);
      }),
    );
    expect(result.hasError, isFalse);
    expect(result.value, isNull);
    expect(calls, 0);
  });

  test('repository keeps GitHub without a native updater', () async {
    for (final gate in [null, () => false]) {
      var calls = 0;
      final result = await http.runWithClient(
        _repository(isNativeUpdaterAvailable: gate).checkUpdate,
        () => MockClient((request) async {
          expect(request.url.host, 'api.github.com');
          calls++;
          return http.Response('{"tag_name":"v9.0.0"}', 200);
        }),
      );
      expect(result.hasError, isFalse);
      expect(result.value?.toString(), play ? isNull : '9.0.0');
      expect(calls, play ? 0 : 1);
    }
  });

  test('server update checks ignore the native updater', () async {
    var calls = 0;
    final repository = AboutRepository(
      client: GraphQLClient(
        link: Link.function((request, [forward]) async* {
          calls++;
          yield Response(
            response: const {},
            data: {
              '__typename': 'Query',
              'checkForServerUpdates': [
                {
                  '__typename': 'CheckForServerUpdatesPayload',
                  'channel': 'Stable',
                  'tag': 'v2.0.0',
                  'url': 'https://server.test/releases',
                },
              ],
            },
          );
        }),
        cache: GraphQLCache(),
      ),
      packageInfo: _packageInfo(),
      isNativeUpdaterAvailable: () => true,
    );
    final updates = await repository.checkServerUpdate();
    expect(calls, 1);
    expect(updates?.single.tag, 'v2.0.0');
  });

  test('wired providers skip GitHub when native is available', () async {
    debugMacOSOverride = true;
    await mockNative(initialize: true);
    final container = ProviderContainer(
      overrides: [
        graphQlClientProvider.overrideWithValue(_emptyClient()),
        packageInfoProvider.overrideWithValue(_packageInfo()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(macOSAppUpdaterProvider).initialize();
    var calls = 0;
    final result = await http.runWithClient(
      container.read(aboutRepositoryProvider).checkUpdate,
      () => MockClient((request) async {
        calls++;
        return http.Response('{"tag_name":"v9.0.0"}', 200);
      }),
    );
    expect(result.hasError, isFalse);
    expect(result.value, isNull);
    expect(calls, 0);
  });
}
