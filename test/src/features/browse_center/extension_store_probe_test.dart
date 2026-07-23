import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';

QueryResult _result({Map<String, dynamic>? data, OperationException? exception}) =>
    QueryResult(
      options: QueryOptions(document: gql_lang.parseString('query { extensionStores { totalCount } }')),
      source: QueryResultSource.network,
      data: data,
      exception: exception,
    );

void main() {
  test('success => supported (definitive true)', () {
    expect(classifyStoreProbe(_result(data: {'extensionStores': {'totalCount': 1}})), true);
  });
  test('GraphQL validation error => old server (definitive false)', () {
    expect(
      classifyStoreProbe(_result(exception: OperationException(
        graphqlErrors: [const GraphQLError(message: 'Cannot query field "extensionStores" on type "Query"')],
      ))),
      false,
    );
  });
  test('transport error => transient (null, never memoized)', () {
    expect(
      classifyStoreProbe(_result(exception: OperationException(
        linkException: ServerException(originalException: Exception('timeout'), parsedResponse: null),
      ))),
      null,
    );
  });
  test('no data, no exception => transient', () {
    expect(classifyStoreProbe(_result()), null);
  });
}
