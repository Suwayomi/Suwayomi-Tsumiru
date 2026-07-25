// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';

/// Scripts a single canned response for whatever request the client sends.
class _FakeLink extends Link {
  _FakeLink(this.response);
  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield response;
  }
}

GraphQLClient _clientWith(Response response) => GraphQLClient(
      link: _FakeLink(response),
      cache: GraphQLCache(),
    );

Response _updateMangasResponse(List<int> ids) => Response(
      data: {
        'updateMangas': {
          'mangas': [
            for (final id in ids) {'id': id, '__typename': 'MangaType'},
          ],
          '__typename': 'UpdateMangasPayload',
        },
        '__typename': 'Mutation',
      },
      response: {},
    );

void main() {
  test('addMangasToLibrary returns the server-confirmed updated ids',
      () async {
    final repo = MangaBookRepository(_clientWith(_updateMangasResponse([5, 9])));

    final result = await repo.addMangasToLibrary([5, 9, 3]);

    expect(result, [5, 9]);
  });

  test('addMangasToLibrary reflects a partial server-side apply', () async {
    // Server only confirmed one of the two requested ids.
    final repo = MangaBookRepository(_clientWith(_updateMangasResponse([5])));

    final result = await repo.addMangasToLibrary([5, 9]);

    expect(result, [5]);
  });
}
