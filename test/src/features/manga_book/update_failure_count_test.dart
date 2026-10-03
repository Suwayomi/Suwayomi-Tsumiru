import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  test('counts failed series without asking for the series', () async {
    Request? sent;
    final client = GraphQLClient(
      link: Link.function((request, [forward]) {
        sent = request;
        return Stream.value(
          Response(
            data: {
              '__typename': 'Query',
              'libraryUpdateStatus': {
                '__typename': 'LibraryUpdateStatus',
                'mangaUpdates': [
                  for (final status in [
                    'FAILED',
                    'COMPLETE',
                    'FAILED',
                    'SKIPPED',
                  ])
                    {'__typename': 'MangaUpdateType', 'status': status},
                ],
              },
            },
            response: const {},
          ),
        );
      }),
      cache: GraphQLCache(),
    );
    final repository = UpdatesRepository(client, client);

    expect(await repository.failedUpdateCount(), 2);
    // Resolving each series is what made the old count cost ~780 KB.
    expect(printNode(sent!.operation.document), isNot(contains('manga {')));
  });
}
