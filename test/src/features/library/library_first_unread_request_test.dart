// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';

void main() {
  Future<Request> libraryRequest({required bool withFirstUnread}) async {
    final requests = <Request>[];
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        requests.add(request);
        return Stream.value(
          Response(
            data: {
              '__typename': 'Query',
              'mangas': {
                '__typename': 'MangaNodeList',
                'nodes': [],
                'pageInfo': {
                  '__typename': 'PageInfo',
                  'hasNextPage': false,
                  'hasPreviousPage': false,
                  'startCursor': null,
                  'endCursor': null,
                },
                'totalCount': 0,
              },
            },
            response: const {},
          ),
        );
      }),
      cache: GraphQLCache(),
    );
    expect(
      await CategoryRepository(
        client,
      ).getAllLibraryMangas(withFirstUnread: withFirstUnread),
      isEmpty,
    );
    return requests.single;
  }

  test('the library asks for the first unread chapter only when the '
      '"continue reading" button is on', () async {
    final off = await libraryRequest(withFirstUnread: false);
    expect(off.variables['withFirstUnread'], isFalse);
    final on = await libraryRequest(withFirstUnread: true);
    expect(on.variables['withFirstUnread'], isTrue);

    final document = printNode(off.operation.document);
    expect(document, contains(r'firstUnreadChapter @include(if: $withFirstUnread)'));
  });

  test('track records come without a separate count', () async {
    final document = printNode(
      (await libraryRequest(withFirstUnread: false)).operation.document,
    );
    final trackRecords = document.substring(document.indexOf('trackRecords'));
    expect(
      trackRecords.substring(0, trackRecords.indexOf('}')),
      isNot(contains('totalCount')),
    );
  });
}
