import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/widget/app_update_dialog.dart';
import 'package:tsumiru/src/features/notifications/controller/notification_settings_providers.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const play = bool.fromEnvironment('TSUMIRU_GOOGLE_PLAY');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('About checks GitHub only outside Play', () async {
    var calls = 0;
    final repository = AboutRepository(
      client: GraphQLClient(
        link: Link.function((request, [forward]) => const Stream.empty()),
        cache: GraphQLCache(),
      ),
      packageInfo: PackageInfo(
        appName: 'Tsumiru',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
    final result = await http.runWithClient(
      repository.checkUpdate,
      () => MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        calls++;
        return http.Response('{"tag_name":"v9.0.0"}', 200);
      }),
    );
    expect(result.hasError, isFalse);
    expect(result.value?.toString(), play ? isNull : '9.0.0');
    expect(calls, play ? 0 : 1);
  });

  test('server update checks remain available in every distribution', () async {
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
      packageInfo: PackageInfo(
        appName: 'Tsumiru',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
    final updates = await repository.checkServerUpdate();
    expect(calls, 1);
    expect(updates?.single.tag, 'v2.0.0');
  });

  test('headless checks GitHub only outside Play', () async {
    var calls = 0;
    const record = BackgroundTokenRecord(gen: 0, authType: 'none');
    final client = NotificationBackgroundClient(
      endpoint: const NotificationEndpoint(baseUrl: 'https://server.test'),
      record: record,
      broker: TokenBroker(
        read: () async => record,
        write: (_) async {},
        refreshFn: (_) async => (tokens: null, transient: false),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        calls++;
        return http.Response(
          '{"tag_name":"v9.0.0","html_url":"https://github.com/release"}',
          200,
        );
      }),
    );
    final result = await client.fetchLatestRelease();
    expect(result?.version, play ? isNull : '9.0.0');
    expect(calls, play ? 0 : 1);
  });

  test('stale app-only worker configurations cannot enable Play checks', () {
    const config = NotificationWorkerConfig(
      serverId: 's',
      endpoint: NotificationEndpoint(baseUrl: 'https://server.test'),
      newChaptersEnabled: false,
      includedCategoryIds: {},
      excludedCategoryIds: {},
      hideContent: false,
      appUpdatesEnabled: true,
    );
    final stale = {...config.toJson(), 'appUpdatesEnabled': true};
    for (final effective in [
      config,
      NotificationWorkerConfig.fromJson(stale),
    ]) {
      expect(effective.appUpdatesEnabled, !play);
      expect(effective.anyEnabled, !play);
      expect(effective.toJson()['appUpdatesEnabled'], !play);
    }
    final extensions = NotificationWorkerConfig.fromJson({
      ...stale,
      'extensionUpdatesEnabled': true,
    });
    expect(extensions.extensionUpdatesEnabled, isTrue);
    expect(extensions.anyEnabled, isTrue);
  });

  test(
    'Play ignores the stored app preference without overwriting it',
    () async {
      SharedPreferences.setMockInitialValues({
        DBKeys.notificationsAppUpdatesEnabled.name: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(notificationsAppUpdatesEnabledProvider), !play);
      if (play) {
        final notifier = container.read(
          notificationsAppUpdatesEnabledProvider.notifier,
        );
        notifier.update(true);
        notifier.updateWithPreviousState((_) => true);
        expect(container.read(notificationsAppUpdatesEnabledProvider), isFalse);
      }
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getBool(DBKeys.notificationsAppUpdatesEnabled.name), isTrue);
    },
  );
  for (final server in [false, true]) {
    testWidgets('update dialog preserves server=$server with no URL', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => appUpdateDialog(
                    title: 'Update target',
                    newRelease: '9.0.0',
                    context: context,
                    toast: null,
                    isServerUpdate: server,
                  ),
                  child: const Text('Open update'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open update'));
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        server || !play ? findsOneWidget : findsNothing,
      );
      if (server) {
        expect(
          find.byType(ElevatedButton),
          play ? findsNothing : findsOneWidget,
        );
      }
    });
  }
}
