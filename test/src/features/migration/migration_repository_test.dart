// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/migration/data/migration_repository.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

void main() {
  for (final failTarget in [false, true]) {
    test(
      'dead source uses stored progress; target failure=$failTarget',
      () async {
        final calls = <String>[];
        final source = testManga();
        final target = source.copyWith(id: 2, inLibrary: false);
        final oldChapter = testChapter().copyWith(
          isRead: true,
          lastPageRead: 2,
        );
        final newChapter = testChapter(id: 20).copyWith(mangaId: 2);
        final client = GraphQLClient(
          cache: GraphQLCache(),
          defaultPolicies: DefaultPolicies(
            query: Policies(fetch: FetchPolicy.noCache),
            mutate: Policies(fetch: FetchPolicy.noCache),
          ),
          link: Link.function((request, [forward]) async* {
            final name = request.operation.document.definitions
                .whereType<OperationDefinitionNode>()
                .single
                .name!
                .value;
            calls.add(name);
            switch (name) {
              case 'GetManga':
                yield Response(
                  response: const {},
                  data: {
                    '__typename': 'Query',
                    'manga': (request.variables['id'] == 1 ? source : target)
                        .toJson(),
                  },
                );
              case 'GetChapterPage':
                expect((request.variables['condition'] as Map)['mangaId'], 1);
                yield Response(
                  response: const {},
                  data: {
                    '__typename': 'Query',
                    'chapters': {
                      '__typename': 'ChapterNodeList',
                      'nodes': [oldChapter.toJson()],
                      'totalCount': 1,
                      'pageInfo': {
                        '__typename': 'PageInfo',
                        'hasNextPage': false,
                        'hasPreviousPage': false,
                      },
                    },
                  },
                );
              case 'GetChaptersByMangaId':
                final id = (request.variables['input'] as Map)['mangaId'];
                if (id == 1 || failTarget) {
                  yield Response(
                    response: const {},
                    errors: [
                      GraphQLError(
                        message: 'Missing source 2528986671771677900',
                      ),
                    ],
                  );
                } else {
                  yield Response(
                    response: const {},
                    data: {
                      '__typename': 'Mutation',
                      'fetchChapters': {
                        '__typename': 'FetchChaptersPayload',
                        'chapters': [newChapter.toJson()],
                      },
                    },
                  );
                }
              case 'UpdateChapter':
                final input = request.variables['input'] as Map;
                expect(input['id'], 20);
                expect((input['patch'] as Map)['isRead'], true);
                yield Response(
                  response: const {},
                  data: {
                    '__typename': 'Mutation',
                    'updateChapter': {
                      '__typename': 'UpdateChapterPayload',
                      'chapter': newChapter.toJson(),
                    },
                  },
                );
              case 'UpdateManga':
                yield Response(
                  response: const {},
                  data: {
                    '__typename': 'Mutation',
                    'updateManga': {
                      '__typename': 'UpdateMangaPayload',
                      'manga': target.copyWith(inLibrary: true).toJson(),
                    },
                  },
                );
              default:
                fail('Unexpected operation: $name');
            }
          }),
        );
        final result = await MigrationRepositoryImpl(
          client,
        ).copyMangaData(1, 2, const MigrationOption(migrateCategories: false));
        expect(
          result.success,
          !failTarget,
          reason: '${result.error} ${result.warnings.join('; ')}',
        );
        expect(calls, contains('GetChapterPage'));
        if (failTarget) {
          expect(calls, isNot(contains('UpdateManga')));
        } else {
          expect(result.migratedChapters, 1);
          expect(
            calls.indexOf('UpdateManga'),
            greaterThan(calls.indexOf('UpdateChapter')),
          );
        }
      },
    );
  }
}
