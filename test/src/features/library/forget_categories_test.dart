import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';

void main() {
  test('failed library removal keeps category assignments', () async {
    final requests = <String>[];
    final repository = MangaBookRepository(
      GraphQLClient(
        cache: GraphQLCache(),
        link: Link.function((request, [forward]) {
          final name = request.operation.document.definitions
              .whereType<OperationDefinitionNode>()
              .single
              .name!
              .value;
          requests.add(name);
          if (name == 'GetWebUiGlobalMetas') {
            return Stream.value(
              Response(
                data: const {
                  '__typename': 'Query',
                  'metas': {
                    '__typename': 'GlobalMetaNodeList',
                    'nodes': [
                      {
                        '__typename': 'GlobalMetaType',
                        'key': 'webUI_removeMangaFromCategories',
                        'value': 'true',
                      },
                    ],
                  },
                },
                response: const {},
              ),
            );
          }
          throw Exception('removal failed');
        }),
      ),
    );
    await expectLater(repository.removeMangaFromLibrary(7), throwsA(anything));
    expect(requests, ['GetWebUiGlobalMetas', 'UpdateManga']);
  });
}
