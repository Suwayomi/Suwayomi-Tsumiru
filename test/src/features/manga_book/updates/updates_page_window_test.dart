// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  group('splitPageWindow', () {
    test('one row past the page means another page follows', () {
      final page = splitPageWindow(List.generate(51, (i) => i), 50);
      expect(page.nodes, List.generate(50, (i) => i));
      expect(page.hasNextPage, isTrue);
    });

    test('a full page and nothing past it is the last page', () {
      final page = splitPageWindow(List.generate(50, (i) => i), 50);
      expect(page.nodes, hasLength(50));
      expect(page.hasNextPage, isFalse);
    });

    test('a short page is the last page', () {
      final page = splitPageWindow([1, 2, 3], 50);
      expect(page.nodes, [1, 2, 3]);
      expect(page.hasNextPage, isFalse);
    });
  });

  test(
    'the Updates query asks for one extra row and no pagination info: '
    'the server would compute a COUNT and two bound lookups for those',
    () async {
      final requests = <Request>[];
      final client = GraphQLClient(
        link: Link.function((request, [forward]) {
          requests.add(request);
          return Stream.value(
            Response(
              data: {
                '__typename': 'Query',
                'chapters': {'__typename': 'ChapterNodeList', 'nodes': []},
              },
              response: const {},
            ),
          );
        }),
        cache: GraphQLCache(),
      );
      final page = await UpdatesRepository(
        client,
        client,
      ).getRecentChaptersPage(pageNo: 2);

      expect(page?.nodes, isEmpty);
      expect(page?.hasNextPage, isFalse);
      final variables = requests.single.variables;
      expect(variables['first'], updatesPageSize + 1);
      // The offset still steps by the page size, not by the window.
      expect(variables['offset'], 2 * updatesPageSize);
      final document = printNode(requests.single.operation.document);
      expect(document, contains('nodes'));
      expect(document, isNot(contains('totalCount')));
      expect(document, isNot(contains('pageInfo')));
    },
  );
}
