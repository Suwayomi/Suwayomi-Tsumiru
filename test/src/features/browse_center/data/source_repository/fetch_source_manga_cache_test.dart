// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';

void main() {
  test('fetchSourceManga reads a payload with no firstUnreadChapter',
      () async {
    final client = GraphQLClient(
      link: Link.function(
        (request, [forward]) => Stream.value(
          Response(
            data: {
              '__typename': 'Mutation',
              'fetchSourceManga': {
                '__typename': 'FetchSourceMangaPayload',
                'hasNextPage': false,
                'mangas': [
                  {
                    '__typename': 'MangaType',
                    'age': null,
                    'artist': null,
                    'author': null,
                    'bookmarkCount': 0,
                    'chapters': {
                      '__typename': 'ChapterNodeList',
                      'totalCount': 0,
                    },
                    'chaptersAge': null,
                    'chaptersLastFetchedAt': null,
                    'description': null,
                    'downloadCount': 0,
                    'genre': <String>[],
                    'id': 1,
                    'inLibrary': false,
                    'inLibraryAt': '0',
                    'initialized': true,
                    'lastFetchedAt': null,
                    'lastReadChapter': null,
                    'latestFetchedChapter': null,
                    'latestUploadedChapter': null,
                    'meta': <Object>[],
                    'realUrl': null,
                    'source': null,
                    'sourceId': '1',
                    'status': 'ONGOING',
                    'thumbnailUrl': null,
                    'thumbnailUrlLastFetched': null,
                    'title': 'Test',
                    'categories': {
                      '__typename': 'CategoryNodeList',
                      'nodes': <Object>[],
                    },
                    'trackRecords': {
                      '__typename': 'TrackRecordNodeList',
                      'nodes': <Object>[],
                    },
                    'unreadCount': 0,
                    'updateStrategy': 'ALWAYS_UPDATE',
                    'url': '/manga/1',
                  },
                ],
              },
            },
            response: const {},
          ),
        ),
      ),
      cache: GraphQLCache(store: InMemoryStore()),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
    final repository = SourceRepository(
      client,
      permissions: AccountPermissionGuard(
        () => AccountAccess(capability: AccountCapability.unsupported),
      ),
    );

    final page = await repository.fetchSourceManga(
      sourceId: '1',
      sourceType: SourceType.POPULAR,
      page: 1,
    );

    expect(page?.hasNextPage, isFalse);
    expect(page?.mangas.single.title, 'Test');
    expect(page?.mangas.single.firstUnreadChapter, isNull);
  });
}
