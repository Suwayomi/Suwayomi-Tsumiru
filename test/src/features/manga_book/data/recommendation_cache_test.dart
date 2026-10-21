import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _Fetch extends RecommendationProvider {
  _Fetch(this.load, {this.label = 'Test'});
  final String label;
  final Future<List<Recommendation>> Function() load;
  @override
  String get name => label;
  @override
  String get category => 'test';
  @override
  Future<List<Recommendation>> fetch(RecommendationContext context) => load();
}

class _Server extends ServerUrl {
  _Server(this.url);
  final String url;
  @override
  String? build() => url;
  void setUrl(String value) => state = value;
}

class _Auth extends AuthCredentialsStore {
  _Auth(this.binding);
  final AccountBinding? binding;
  @override
  Future<AuthCredentialsState> build() async =>
      AuthCredentialsState(accountBinding: binding);
}

const _saved = Recommendation(title: 'Saved', category: 'test');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late http.Client client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'serverPortToggle': false});
    prefs = await SharedPreferences.getInstance();
    client = http.Client();
    addTearDown(client.close);
  });
  ProviderContainer create({
    String server = 'https://one',
    String title = 'Example',
    int? user,
    required Future<List<Recommendation>> Function() fetch,
    bool defaultRetry = false,
    bool healthy = false,
  }) {
    final provider = _Fetch(fetch);
    final container = ProviderContainer(
      retry: defaultRetry ? null : (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authTypeKeyProvider.overrideWithValue(
          user == null ? AuthType.none : AuthType.uiLogin,
        ),
        authCredentialsStoreProvider.overrideWith(
          () => _Auth(
            user == null
                ? null
                : AccountBinding(
                    address: server,
                    userId: user,
                    username: 'reader',
                    catalogId: 'catalog',
                  ),
          ),
        ),
        serverUrlProvider.overrideWith(() => _Server(server)),
        recommendationSetupProvider(1).overrideWith(
          (ref) async => (
            ctx: RecommendationContext(
              title: title,
              remoteIdByTracker: const {},
              sourceName: '',
              mangaUrl: null,
              client: client,
            ),
            providers: [
              provider,
              if (healthy) _Fetch(() async => [_saved], label: 'Healthy'),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<Recommendation>> run({
    String server = 'https://one',
    String title = 'Example',
    int? user,
    bool fail = false,
  }) async {
    final container = create(
      server: server,
      title: title,
      user: user,
      fetch: () async {
        if (fail) throw StateError('offline');
        return [_saved];
      },
    );
    return container.read(
      providerRecommendationsProvider(1, 'Test|test').future,
    );
  }

  test(
    'a different server cannot reuse the same manga recommendation cache',
    () async {
      await run();
      await expectLater(
        run(server: 'https://two', fail: true),
        throwsStateError,
      );
      await run(server: 'https://two');
      expect(
        (await run(server: 'https://two', fail: true)).single.title,
        'Saved',
      );
    },
  );
  test(
    'a different title cannot reuse the same manga recommendation cache',
    () async {
      await run();
      await expectLater(run(title: 'Different', fail: true), throwsStateError);
    },
  );
  test(
    'a different account on the same server cannot reuse cached recommendations',
    () async {
      await run(user: 1);
      await expectLater(run(user: 2, fail: true), throwsStateError);
      await run(user: 2);
      expect((await run(user: 2, fail: true)).single.title, 'Saved');
    },
  );
  test('legacy unscoped cache entries are ignored and retained', () async {
    final legacy = jsonEncode([_saved.toJson()]);
    await prefs.setString('recsCache:1:Test|test', legacy);
    await expectLater(run(fail: true), throwsStateError);
    expect(prefs.getString('recsCache:1:Test|test'), legacy);
  });
  test(
    'equivalent URLs share a cache and URL credentials never enter its key',
    () async {
      await run(
        server: 'HTTPS://person:secret@one:443/base/?token=hidden#fragment',
      );
      expect(
        (await run(server: 'https://one/base', fail: true)).single.title,
        'Saved',
      );
      final key = prefs
          .getKeys()
          .where((key) => key.startsWith('recsCache:v2:'))
          .single;
      expect(key, isNot(contains('secret')));
      expect(key, isNot(contains('hidden')));
      expect(key, isNot(contains('person')));
      await expectLater(
        run(server: 'https://one/other', fail: true),
        throwsStateError,
      );
    },
  );
  test(
    'pending requests retain the identity captured before fetching',
    () async {
      final pending = Completer<List<Recommendation>>();
      var calls = 0;
      final container = create(
        fetch: () {
          if (++calls == 1) return pending.future;
          throw StateError('offline');
        },
      );
      final individual = providerRecommendationsProvider(1, 'Test|test');
      container.listen(individual, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      (container.read(serverUrlProvider.notifier) as _Server).setUrl(
        'https://two',
      );
      await Future<void>.delayed(Duration.zero);
      pending.complete([_saved]);
      await Future<void>.delayed(Duration.zero);
      await expectLater(container.read(individual.future), throwsStateError);
      expect(
        prefs.getKeys().any(
          (key) =>
              key.contains('https://two') && key.startsWith('recsCache:v2:'),
        ),
        isFalse,
      );
    },
  );
  for (final error in [
    const RecommendationHttpException(403),
    const RecommendationServiceUnavailable(),
    const RecommendationUnavailableOnWeb(),
  ]) {
    test(
      'terminal $error settles once under default Riverpod retry policy',
      () {
        fakeAsync((clock) {
          var calls = 0;
          final container = create(
            defaultRetry: true,
            fetch: () async {
              calls++;
              throw error;
            },
          );
          final individual = providerRecommendationsProvider(1, 'Test|test');
          container.listen(individual, (_, _) {});
          container.listen(mangaRecommendationsProvider(1), (_, _) {});
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 40));
          clock.flushMicrotasks();
          expect(calls, 1);
          expect(container.read(individual).isLoading, isFalse);
          expect(
            container.read(mangaRecommendationsProvider(1)).hasError,
            isTrue,
          );
        });
      },
    );
  }
  test(
    'a healthy provider remains visible beside a terminal failure with default retry',
    () {
      fakeAsync((clock) {
        var calls = 0;
        final container = create(
          defaultRetry: true,
          healthy: true,
          fetch: () async {
            calls++;
            throw const RecommendationServiceUnavailable();
          },
        );
        container.listen(mangaRecommendationsProvider(1), (_, _) {});
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 40));
        clock.flushMicrotasks();
        expect(calls, 1);
        expect(
          container.read(mangaRecommendationsProvider(1)).value?.single.title,
          'Saved',
        );
      });
    },
  );
  test(
    'setup errors settle once with default retry and remain available for manual retry',
    () {
      fakeAsync((clock) {
        var calls = 0;
        final container = ProviderContainer(
          overrides: [
            recommendationSetupProvider(1).overrideWith((ref) async {
              calls++;
              throw StateError('setup failed');
            }),
          ],
        );
        addTearDown(container.dispose);
        container.listen(mangaRecommendationsProvider(1), (_, _) {});
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 40));
        clock.flushMicrotasks();
        expect(calls, 1);
        expect(
          container.read(mangaRecommendationsProvider(1)).isLoading,
          isFalse,
        );
        expect(
          container.read(mangaRecommendationsProvider(1)).hasError,
          isTrue,
        );
      });
    },
  );
}
