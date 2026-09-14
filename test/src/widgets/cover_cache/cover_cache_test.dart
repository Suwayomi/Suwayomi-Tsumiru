// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_cover_warmer.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';

class _SessionStore extends AuthCredentialsStore {
  int epoch = 0;
  AuthCredentialsState credentials = const AuthCredentialsState();
  void adopt(String catalogId) {
    epoch++;
    credentials = AuthCredentialsState(
      accountBinding: AccountBinding(
        address: 'http://server',
        username: catalogId,
        userId: 1,
        catalogId: catalogId,
      ),
      uiAccessToken: 'token-for-test',
    );
    state = AsyncData(credentials);
  }

  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => credentials;
}

class _UiLogin extends AuthTypeKey {
  @override
  AuthType? build() => AuthType.uiLogin;
}

class _LateDownloadCache extends _RecordingCacheManager {
  final entered = Completer<void>();
  final release = Completer<void>();
  final lookups = <String>[];
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) {
    lookups.add(key);
    return super.getFileFromCache(key, ignoreMemCache: ignoreMemCache);
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    final result = await super.downloadFile(
      url,
      key: key,
      authHeaders: authHeaders,
      force: force,
    );
    cachedKeys.add(key ?? url);
    return result;
  }
}

class _DelayedCacheManager extends _RecordingCacheManager {
  final entered = Completer<void>();
  final lookup = Completer<FileInfo?>();
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) {
    if (!entered.isCompleted) entered.complete();
    return lookup.future;
  }
}

/// Records cache traffic; [cachedKeys] entries answer getFileFromCache.
class _RecordingCacheManager extends Fake implements CacheManager {
  final cachedKeys = <String>{};
  final downloads =
      <({String url, String key, Map<String, String>? headers})>[];

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    if (!cachedKeys.contains(key)) return null;
    final file = MemoryFileSystem().file('cover')..writeAsBytesSync([1]);
    return FileInfo(file, FileSource.Cache, DateTime(2100), key);
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloads.add((url: url, key: key ?? url, headers: authHeaders));
    final file = MemoryFileSystem().file('cover')..writeAsBytesSync([1]);
    return FileInfo(file, FileSource.Online, DateTime(2100), url);
  }
}

MangaDto _manga(int id, {String? thumbnailUrl}) => MangaDto(
  id: id,
  title: 'Manga $id',
  thumbnailUrl: thumbnailUrl,
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 1),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late account A cover is never reused for account B', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _SessionStore();
    final cache = _LateDownloadCache();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(() => auth),
        authTypeKeyProvider.overrideWith(_UiLogin.new),
        coverCacheManagerProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    auth.adopt('account-a');
    final warmer = container.read(offlineCoverWarmerProvider.notifier);
    final manga = [_manga(1, thumbnailUrl: '/manga/1/thumbnail')];
    final first = warmer.warmLibraryCovers(manga);
    await cache.entered.future;
    auth.adopt('account-b');
    cache.release.complete();
    await first;
    await warmer.warmLibraryCovers(manga);
    expect(cache.downloads, hasLength(2));
    expect(cache.downloads[0].key, isNot(cache.downloads[1].key));
    expect(cache.lookups[0], cache.downloads[0].key);
    expect(cache.lookups[1], cache.downloads[1].key);
    expect(
      cache.downloads.every((entry) => entry.url.startsWith('http')),
      isTrue,
    );
    auth.adopt('account-a');
    await warmer.warmLibraryCovers(manga);
    expect(cache.downloads, hasLength(2));
    expect(cache.lookups.last, cache.downloads.first.key);
  });

  test('account replacement cancels a pending cover cache lookup', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _SessionStore();
    final cache = _DelayedCacheManager();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(() => auth),
        coverCacheManagerProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    final pending = container
        .read(offlineCoverWarmerProvider.notifier)
        .warmLibraryCovers([_manga(1, thumbnailUrl: '/manga/1/thumbnail')]);
    await cache.entered.future;
    auth.epoch++;
    cache.lookup.complete(null);
    await pending;
    expect(cache.downloads, isEmpty);
  });

  group('isCoverImagePath', () {
    test('routes covers and source icons to the durable cache', () {
      expect(isCoverImagePath('/api/v1/manga/12/thumbnail'), isTrue);
      expect(isCoverImagePath('/api/v1/extension/icon/foo.apk'), isTrue);
    });

    test('leaves chapter pages on the default cache', () {
      expect(isCoverImagePath('/api/v1/manga/12/chapter/3/page/0'), isFalse);
    });
  });

  group('OfflineCoverWarmer', () {
    late _RecordingCacheManager cache;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'flutter.serverUrl': 'http://server.test',
        'flutter.serverPortToggle': false,
      });
      final prefs = await SharedPreferences.getInstance();
      cache = _RecordingCacheManager();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          coverCacheManagerProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
      'downloads missing library covers under the un-tokened cache key',
      () async {
        await container
            .read(offlineCoverWarmerProvider.notifier)
            .warmLibraryCovers([
              _manga(1, thumbnailUrl: '/api/v1/manga/1/thumbnail'),
              _manga(2, thumbnailUrl: '/api/v1/manga/2/thumbnail'),
            ]);
        expect(cache.downloads.map((d) => d.key).toSet(), {
          'http://server.test/api/v1/manga/1/thumbnail',
          'http://server.test/api/v1/manga/2/thumbnail',
        });
      },
    );

    test('skips covers already in the cache', () async {
      cache.cachedKeys.add('http://server.test/api/v1/manga/1/thumbnail');
      await container
          .read(offlineCoverWarmerProvider.notifier)
          .warmLibraryCovers([
            _manga(1, thumbnailUrl: '/api/v1/manga/1/thumbnail'),
            _manga(2, thumbnailUrl: '/api/v1/manga/2/thumbnail'),
          ]);
      expect(cache.downloads.map((d) => d.key).toList(), [
        'http://server.test/api/v1/manga/2/thumbnail',
      ]);
    });

    test('ignores manga with no thumbnail', () async {
      await container
          .read(offlineCoverWarmerProvider.notifier)
          .warmLibraryCovers([_manga(1, thumbnailUrl: null)]);
      expect(cache.downloads, isEmpty);
    });
  });
}
