// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';

class _Cache extends Fake implements CacheManager {
  final cachedKeys = <String>{};
  final downloads =
      <({String url, String key, Map<String, String>? headers})>[];

  FileInfo _info(String key, FileSource source) {
    final file = MemoryFileSystem().file('cover')..writeAsBytesSync([7]);
    return FileInfo(file, source, DateTime(2100), key);
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => cachedKeys.contains(key) ? _info(key, FileSource.Cache) : null;

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    downloads.add((url: url, key: key ?? url, headers: authHeaders));
    cachedKeys.add(key ?? url);
    return _info(url, FileSource.Online);
  }
}

class _Store extends AuthCredentialsStore {}

BackgroundTokenRecord _record(String authType) => BackgroundTokenRecord(
  gen: 0,
  authType: authType,
  endpoint: 'https://server|-',
  identityEpoch: 0,
  catalogServerId: 'catalog',
  accessToken: 'token',
  basicCredential: 'Basic abc',
);

void main() {
  const app = NotificationEndpoint(baseUrl: 'https://server', addPort: false);
  const lan = NotificationEndpoint(baseUrl: 'http://lan', addPort: false);
  const cover = '/api/v1/manga/1/thumbnail';

  var httpCalls = 0;
  NotificationBackgroundClient client(String authType, _Cache cache) =>
      NotificationBackgroundClient(
        endpoint: lan,
        cacheEndpoint: app,
        record: _record(authType),
        broker: TokenBroker(
          read: () async => _record(authType),
          write: (_) async {},
          refreshFn: (_) async => (tokens: null, transient: false),
        ),
        httpClient: MockClient((_) async {
          httpCalls++;
          return http.Response('', 200);
        }),
        coverCache: cache,
      );

  setUp(() => httpCalls = 0);

  test(
    'uses the key the app stores the cover under, and fetches it once',
    () async {
      final appKey = accountImageCacheKey(
        'https://server$cover',
        authType: AuthType.uiLogin,
        store: _Store(),
        credentials: AuthCredentialsState(
          accountBinding: AccountBinding(
            address: 'https://server',
            username: 'u',
            userId: 1,
            catalogId: 'catalog',
          ),
        ),
        coverVersion: '5',
      );
      final cache = _Cache();
      final c = client('uiLogin', cache);

      expect(await c.fetchCover(cover, coverVersion: '5'), [7]);
      expect(cache.downloads.single.key, appKey);
      // Fetched from this network's address, with the account's credentials.
      expect(cache.downloads.single.url, 'http://lan$cover');
      expect(cache.downloads.single.headers?['Authorization'], 'Bearer token');

      expect(await c.fetchCover(cover, coverVersion: '5'), [7]);
      expect(cache.downloads, hasLength(1));
      expect(httpCalls, 0);
    },
  );

  test('legacy auth keys by URL and version, like the app', () async {
    final cache = _Cache()..cachedKeys.add('https://server$cover#cover-5');
    expect(await client('basic', cache).fetchCover(cover, coverVersion: '5'), [
      7,
    ]);
    expect(cache.downloads, isEmpty);
  });

  test(
    'external custom covers go without credentials under their URL',
    () async {
      final cache = _Cache();
      const external = 'https://elsewhere/cover.jpg';
      await client('basic', cache).fetchCover(external);
      expect(cache.downloads.single.key, external);
      expect(cache.downloads.single.headers, isEmpty);
    },
  );
}
