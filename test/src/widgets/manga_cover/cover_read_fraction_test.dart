// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

void main() {
  group('coverReadFraction', () {
    test('reports the read fraction', () {
      expect(coverReadFraction(totalChapters: 10, unreadCount: 3), 0.7);
      expect(coverReadFraction(totalChapters: 8, unreadCount: 0), 1.0);

      // Nothing read, no chapters or more unread than total -> null.
      expect(coverReadFraction(totalChapters: 10, unreadCount: 10), isNull);
      expect(coverReadFraction(totalChapters: 0, unreadCount: 0), isNull);
      // Clamps instead of going negative.
      expect(coverReadFraction(totalChapters: 5, unreadCount: 9), isNull);
    });
  });

  group('custom cover', () {
    testWidgets('library cover shows the custom link, server cover after clear', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = _StillCache();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authTypeKeyProvider.overrideWith(_NoAuth.new),
          credentialsProvider.overrideWith(_NoBasic.new),
          authCredentialsStoreProvider.overrideWith(_EmptySession.new),
          customHttpHeadersProvider.overrideWith(_NoCustomHeaders.new),
          coverCacheManagerProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(cache.close);

      const thumb = '/api/v1/manga/1/thumbnail';
      const custom = 'https://cdn.example.com/covers/1.jpg';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 300,
                child: MangaCoverGridTile(
                  manga: _coverManga(thumb, custom),
                  showTitle: false,
                  showBadges: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      var drawn = tester.widget<ServerImage>(find.byType(ServerImage));
      expect(drawn.imageUrl, custom);
      expect(drawn.fallbackImageUrl, thumb);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 300,
                child: MangaCoverGridTile(
                  manga: _coverManga(thumb, null),
                  showTitle: false,
                  showBadges: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      drawn = tester.widget<ServerImage>(find.byType(ServerImage));
      expect(drawn.imageUrl, thumb);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('cover cache key changes when the server cover timestamp changes', () {
      String key(String? version) => accountImageCacheKey(
        'https://server.example/api/v1/manga/1/thumbnail',
        authType: AuthType.basic,
        store: _EmptySession(),
        credentials: null,
        coverVersion: version,
      );
      expect(key(null), 'https://server.example/api/v1/manga/1/thumbnail');
      expect(key('100'), isNot(key('200')));
      expect(key('100'), isNot(key(null)));
    });
  });
}

Fragment$MangaDto _coverManga(String thumb, String? custom) =>
    Fragment$MangaDto(
      id: 1,
      title: 'Series',
      thumbnailUrl: thumb,
      chapters: Fragment$MangaDto$chapters(totalCount: 4),
      genre: const [],
      initialized: true,
      meta: custom == null
          ? const []
          : [
              Fragment$MangaDto$meta(
                key: MangaMetaKeys.customCover.key,
                value: custom,
              ),
            ],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
      user: Fragment$MangaDto$user(
        bookmarkCount: 0,
        downloadCount: 0,
        inLibrary: true,
        inLibraryAt: '0',
        unreadCount: 0,
      ),
    );

class _NoAuth extends AuthTypeKey {
  @override
  AuthType? build() => null;
}

class _NoBasic extends Credentials {
  @override
  Future<String?> build() async => null;
}

class _EmptySession extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _NoCustomHeaders extends CustomHttpHeadersStore {
  @override
  Future<Map<String, String>> build() async => const {};
}

class _StillCache extends Fake implements CacheManager {
  final _events = StreamController<FileResponse>.broadcast();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => _events.stream;

  Future<void> close() => _events.close();
}
