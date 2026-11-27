import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/data/macos_app_updater.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

const _channel = MethodChannel('tsumiru/sparkle_updater');

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Tsumiru',
  packageName: 'test',
  version: '1.0.0',
  buildNumber: '1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int initializeCalls;

  setUp(() {
    initializeCalls = 0;
    debugMacOSOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          return switch (call.method) {
            'initialize' => () {
              initializeCalls++;
              return true;
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

  test('restart keeps the initialized updater without re-init', () async {
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isTrue);
    final old = ProviderContainer(
      overrides: [macOSAppUpdaterProvider.overrideWithValue(updater)],
    );
    final next = ProviderContainer(
      overrides: [
        macOSAppUpdaterProvider.overrideWithValue(
          old.read(macOSAppUpdaterProvider),
        ),
      ],
    );
    addTearDown(next.dispose);
    old.dispose();

    expect(next.read(macOSAppUpdaterProvider), same(updater));
    expect(await next.read(macOSAppUpdaterProvider).checkForUpdates(), isTrue);
    expect(initializeCalls, 1);
  });

  test('server update checks ignore the native updater', () async {
    final updater = MacOSAppUpdater();
    expect(await updater.initialize(), isTrue);
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
    );
    final updates = await repository.checkServerUpdate();
    expect(calls, 1);
    expect(initializeCalls, 1);
    expect(updater.isAvailable, isTrue);
    expect(updates?.single.tag, 'v2.0.0');
  });
}
