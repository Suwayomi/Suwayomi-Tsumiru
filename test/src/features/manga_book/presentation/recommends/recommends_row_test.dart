import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_provider.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/recommends_row.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/widgets/cover_row_section.dart';

const _one = Recommendation(title: 'First result', category: 'test');
const _two = Recommendation(title: 'Later result', category: 'test');
final _results = NotifierProvider<_Results, AsyncValue<List<Recommendation>>>(
  _Results.new,
);

class _Results extends Notifier<AsyncValue<List<Recommendation>>> {
  @override
  AsyncValue<List<Recommendation>> build() => const AsyncLoading();
  void set(AsyncValue<List<Recommendation>> value) => state = value;
}

final _lookupIds = NotifierProvider<_LookupIds, Map<String, String>>(
  _LookupIds.new,
);

class _LookupIds extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {'mangaupdates': '1', 'anilist': '7'};
  void set(Map<String, String> value) => state = value;
}

class _Auth extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
  void switchAccount() => state = const AsyncData(
    AuthCredentialsState(
      sessionEpoch: 1,
      accountBinding: AccountBinding(
        address: 'https://one',
        userId: 2,
        username: 'second',
        catalogId: 'second',
      ),
    ),
  );
}

class _Server extends ServerUrl {
  @override
  String? build() => 'https://one';
  void switchServer() => state = 'https://two';
}

class _FetchProvider extends RecommendationProvider {
  _FetchProvider(this.load);
  final Future<List<Recommendation>> Function(RecommendationContext) load;
  @override
  String get name => 'Test service';
  @override
  String get category => 'test';
  @override
  Future<List<Recommendation>> fetch(RecommendationContext context) =>
      load(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'));
    await loader.load();
  });
  late ProviderContainer container;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  Future<void> pump(
    WidgetTester tester, {
    Future<List<Recommendation>> Function()? fetch,
    Future<List<Recommendation>> Function(RecommendationContext)? lookupFetch,
    ValueNotifier<int>? manga,
    double scale = 1,
    VoidCallback? onSetup,
    bool offline = false,
  }) async {
    final client = http.Client();
    addTearDown(client.close);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(_Auth.new),
        serverUrlProvider.overrideWith(_Server.new),
        for (final id in [1, 2])
          recommendationSetupProvider(id).overrideWith((ref) async {
            onSetup?.call();
            return (
              ctx: RecommendationContext(
                title: 'Example',
                remoteIdByTracker: ref.watch(_lookupIds),
                sourceName: '',
                mangaUrl: null,
                client: client,
              ),
              providers: [
                if (fetch != null) _FetchProvider((_) => fetch()),
                if (lookupFetch != null) _FetchProvider(lookupFetch),
              ],
            );
          }),
        if (fetch == null && lookupFetch == null)
          mangaRecommendationsProvider(
            1,
          ).overrideWith((ref) => ref.watch(_results)),
        mangaRecommendationsProvider(
          2,
        ).overrideWith((ref) => ref.watch(_results)),
      ],
    );
    addTearDown(container.dispose);
    if (offline) container.read(serverUnreachableProvider.notifier).set(true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(
            theme: AppTheme.indigoNight,
            brightness: Brightness.dark,
            customSeed: const Color(0xFF7C7BFF),
            amoled: false,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: manga == null
              ? const Scaffold(body: RecommendsRow(mangaId: 1))
              : ValueListenableBuilder<int>(
                  valueListenable: manga,
                  builder: (context, id, child) =>
                      Scaffold(body: RecommendsRow(mangaId: id)),
                ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'loading explains the work and keeps the full suggestions action',
    (tester) async {
      await pump(tester);
      expect(find.text('Fetching suggestions…'), findsOneWidget);
      expect(
        find.text('Checking recommendation services. This may take a moment.'),
        findsOneWidget,
      );
      expect(
        tester.widget<CoverRowSection>(find.byType(CoverRowSection)).onSeeAll,
        isNotNull,
      );
    },
  );
  testWidgets('settled empty results remain visible with Retry', (
    tester,
  ) async {
    await pump(tester);
    container.read(_results.notifier).set(const AsyncData([]));
    await tester.pump();
    expect(find.text('No suggestions found for this title.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('failed results remain visible with Retry', (tester) async {
    await pump(tester);
    container
        .read(_results.notifier)
        .set(AsyncError(StateError('failed'), StackTrace.current));
    await tester.pump();
    expect(
      find.text('Couldn’t load suggestions. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('a lone unavailable provider names itself', (tester) async {
    await pump(
      tester,
      fetch: () async {
        throw const RecommendationServiceUnavailable();
      },
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Test service is temporarily unavailable. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('every provider unavailable names them all', (tester) async {
    await pump(tester);
    container
        .read(_results.notifier)
        .set(
          AsyncError<List<Recommendation>>(
            const RecommendationAllFailed([
              RecommendationProviderFailure(
                'AniList',
                RecommendationServiceUnavailable(),
              ),
              RecommendationProviderFailure(
                'MangaUpdates',
                RecommendationServiceUnavailable(),
              ),
              RecommendationProviderFailure(
                'MyAnimeList',
                RecommendationServiceUnavailable(),
              ),
            ]),
            StackTrace.current,
          ),
        );
    await tester.pump();
    expect(
      find.text(
        "Couldn't load recommendations from "
        'AniList, MangaUpdates, MyAnimeList. Try again later.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('mixed provider failures name every provider', (tester) async {
    await pump(tester);
    container
        .read(_results.notifier)
        .set(
          AsyncError<List<Recommendation>>(
            const RecommendationAllFailed([
              RecommendationProviderFailure(
                'AniList',
                RecommendationServiceUnavailable(),
              ),
              RecommendationProviderFailure(
                'MyAnimeList',
                RecommendationHttpException(403),
              ),
            ]),
            StackTrace.current,
          ),
        );
    await tester.pump();
    expect(
      find.text(
        "Couldn't load recommendations from AniList, MyAnimeList. "
        'Try again later.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('first visible cards do not change after later results', (
    tester,
  ) async {
    await pump(tester);
    container.read(_results.notifier).set(const AsyncData([_one]));
    await tester.pump();
    container.read(_results.notifier).set(const AsyncData([_two, _one]));
    await tester.pump();
    expect(find.text('First result'), findsOneWidget);
    expect(find.text('Later result'), findsNothing);
  });
  for (final account in [false, true]) {
    testWidgets('snapshot resets for a new ${account ? 'account' : 'server'}', (
      tester,
    ) async {
      await pump(tester);
      container.read(_results.notifier).set(const AsyncData([_one]));
      await tester.pump();
      container.read(_results.notifier).set(const AsyncData([_two]));
      if (account) {
        (container.read(authCredentialsStoreProvider.notifier) as _Auth)
            .switchAccount();
      } else {
        (container.read(serverUrlProvider.notifier) as _Server).switchServer();
      }
      await tester.pump();
      expect(find.text('Later result'), findsOneWidget);
      expect(find.text('First result'), findsNothing);
    });
  }
  testWidgets('snapshot resets when the same manga changes tracker lookup', (
    tester,
  ) async {
    await pump(tester);
    container.read(_results.notifier).set(const AsyncData([_one]));
    await tester.pump();
    container.read(_lookupIds.notifier).set({
      'mangaupdates': '2',
      'anilist': '7',
    });
    container.read(_results.notifier).set(const AsyncData([_two]));
    await tester.pump();
    await tester.pump();
    expect(find.text('Later result'), findsOneWidget);
    expect(find.text('First result'), findsNothing);
  });
  testWidgets(
    'recreated setup and reordered tracker map keep the first cards',
    (tester) async {
      await pump(tester);
      container.read(_results.notifier).set(const AsyncData([_one]));
      await tester.pump();
      container.read(_lookupIds.notifier).set({
        'anilist': '7',
        'mangaupdates': '1',
      });
      container.read(_results.notifier).set(const AsyncData([_two]));
      await tester.pump();
      await tester.pump();
      expect(find.text('First result'), findsOneWidget);
      expect(find.text('Later result'), findsNothing);
    },
  );
  testWidgets('disabled Suggestions never start recommendation setup', (
    tester,
  ) async {
    await prefs.setBool('showRecommendations', false);
    var setupCalls = 0;
    await pump(tester, onSetup: () => setupCalls++);
    expect(find.byType(CoverRowSection), findsNothing);
    expect(setupCalls, 0);
  });

  testWidgets('offline Suggestions never start recommendation setup', (
    tester,
  ) async {
    var setupCalls = 0;
    await pump(tester, offline: true, onSetup: () => setupCalls++);
    expect(find.byType(CoverRowSection), findsNothing);
    expect(setupCalls, 0);
  });

  testWidgets(
    'a new lookup waits for fresh provider results instead of refreezing old data',
    (tester) async {
      final pending = Completer<List<Recommendation>>();
      await pump(
        tester,
        lookupFetch: (context) async =>
            context.remoteIdByTracker['mangaupdates'] == '1'
            ? [_one]
            : pending.future,
      );
      await tester.pumpAndSettle();
      expect(find.text('First result'), findsOneWidget);
      container.read(_lookupIds.notifier).set({
        'mangaupdates': '2',
        'anilist': '7',
      });
      await tester.pump();
      await tester.pump();
      expect(container.read(mangaRecommendationsProvider(1)).isLoading, isTrue);
      expect(find.text('First result'), findsNothing);
      expect(find.text('Fetching suggestions…'), findsOneWidget);
      pending.complete([_two]);
      await tester.pumpAndSettle();
      expect(find.text('Later result'), findsOneWidget);
      expect(find.text('First result'), findsNothing);
    },
  );

  testWidgets('Retry starts the actual provider fetch again', (tester) async {
    var calls = 0;
    await pump(tester, fetch: () async => ++calls == 1 ? [] : [_two]);
    await tester.pumpAndSettle();
    expect(find.text('No suggestions found for this title.'), findsOneWidget);
    expect(calls, 1);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Later result'), findsOneWidget);
  });

  testWidgets('snapshot resets for a new manga without remounting', (
    tester,
  ) async {
    final manga = ValueNotifier(1);
    addTearDown(manga.dispose);
    await pump(tester, manga: manga);
    container.read(_results.notifier).set(const AsyncData([_one]));
    await tester.pump();
    container.read(_results.notifier).set(const AsyncData([_two]));
    manga.value = 2;
    await tester.pump();
    expect(find.text('Later result'), findsOneWidget);
    expect(find.text('First result'), findsNothing);
  });

  testWidgets(
    'loading, empty and error fit360dp at text scale2 without changing height',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, scale: 2);
      final height = tester.getSize(find.byType(CoverRowSection)).height;
      expect(tester.takeException(), isNull);
      for (final state in [
        const AsyncData<List<Recommendation>>([]),
        AsyncError<List<Recommendation>>(
          StateError('failed'),
          StackTrace.current,
        ),
      ]) {
        container.read(_results.notifier).set(state);
        await tester.pump();
        expect(tester.getSize(find.byType(CoverRowSection)).height, height);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
