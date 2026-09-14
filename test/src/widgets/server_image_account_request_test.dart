import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_page_actions_sheet.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/cache_manager_extensions.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

class _Session extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
  void adopt(String id, String token) {
    if (state.value?.accountBinding?.catalogId != id) epoch++;
    state = AsyncData(
      AuthCredentialsState(
        sessionEpoch: epoch,
        uiAccessToken: token,
        accountBinding: AccountBinding(
          address: 'http://server',
          username: id,
          catalogId: id,
        ),
      ),
    );
  }
}

class _UiLogin extends AuthTypeKey {
  @override
  AuthType? build() => AuthType.uiLogin;
}

class _Basic extends Credentials {
  @override
  Future<String?> build() async => null;
}

class _Cache extends Fake implements CacheManager {
  bool online = true;
  final entries = <String, File>{};
  final reads = <String>[];
  final files = MemoryFileSystem();
  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    final cacheKey = key ?? url;
    reads.add(cacheKey);
    if (entries[cacheKey] case final File cached) return cached;
    if (!online) throw StateError('Offline cache miss');
    return entries[cacheKey] = files.file('/page.png')..writeAsBytesSync([1]);
  }

  final stream = StreamController<FileResponse>.broadcast();
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => stream.stream;
}

void main() {
  testWidgets(
    'paged prefetch is reused by rendering and offline sharing only for its account',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = _Session();
      final cache = _Cache();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authCredentialsStoreProvider.overrideWith(() => auth),
          authTypeKeyProvider.overrideWith(_UiLogin.new),
          credentialsProvider.overrideWith(_Basic.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      auth.adopt('account-a', 'token-a');
      late WidgetRef readerRef;
      const page = '/api/v1/manga/1/chapter/0/page/0';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                readerRef = ref;
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showReaderPageActionsSheet(
                      context: context,
                      ref: ref,
                      cacheManager: cache,
                      chapterPages: ChapterPagesDto(
                        chapter: ChapterPagesChapterDto(id: 1, pageCount: 1),
                        pages: const [page],
                      ),
                      pageIndex: 0,
                    ),
                    child: const Text('Actions'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final prefetched = await cache.getServerFile(readerRef, page);
      final keyA = cache.reads.single;
      final requestA = serverImageRequest(readerRef, page);
      expect(requestA.cacheKey, keyA);
      cache.online = false;
      expect(
        await cache.getSingleFile(requestA.fetchUrl, key: requestA.cacheKey),
        same(prefetched),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      await tester.tap(find.byKey(const ValueKey('reader-page-action-share')));
      await tester.pumpAndSettle();
      expect(cache.reads.last, keyA);
      expect(cache.entries.length, 1);
      cache.entries[requestA.fetchUrl.split('?').first] = prefetched as File;
      auth.adopt('account-b', 'token-b');
      await expectLater(cache.getServerFile(readerRef, page), throwsStateError);
      expect(cache.reads.last, isNot(keyA));
      expect(cache.reads.last, isNot(requestA.fetchUrl));
      auth.adopt('account-a', 'token-a-new');
      expect(await cache.getServerFile(readerRef, page), same(prefetched));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('widget raw request and prefetch share stable account keys', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _Session();
    final cache = _Cache();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(() => auth),
        authTypeKeyProvider.overrideWith(_UiLogin.new),
        credentialsProvider.overrideWith(_Basic.new),
        coverCacheManagerProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(cache.stream.close);
    await container.read(authCredentialsStoreProvider.future);
    auth.adopt('account-a', 'token-a');
    late String requestKey;
    late String requestUrl;
    late CachedNetworkImageProvider prefetch;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(authCredentialsStoreProvider);
              final request = serverImageRequest(ref, '/manga/1/thumbnail');
              requestKey = request.cacheKey;
              requestUrl = request.fetchUrl;
              prefetch =
                  serverPageImageProvider(ref, '/manga/1/thumbnail')
                      as CachedNetworkImageProvider;
              return const ServerImage(imageUrl: '/manga/1/thumbnail');
            },
          ),
        ),
      ),
    );
    final first = requestKey;
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .cacheKey,
      first,
    );
    expect(prefetch.cacheKey, first);
    expect(prefetch.url, requestUrl);
    expect(Uri.parse(requestUrl).scheme, 'http');
    expect(requestUrl, isNot(contains('tsumiru-image:')));
    auth.adopt('account-a', 'token-rotated');
    await tester.pump();
    expect(requestKey, first);
    auth.adopt('account-b', 'token-b');
    await tester.pump();
    expect(requestKey, isNot(first));
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .cacheKey,
      requestKey,
    );
    expect(prefetch.cacheKey, requestKey);
    auth.adopt('account-a', 'token-return');
    await tester.pump();
    expect(requestKey, first);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
