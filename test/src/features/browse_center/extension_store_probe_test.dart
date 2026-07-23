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

/// Scripted link: replays [outcomes] in order (Response = answer, anything
/// else = stream error), counting requests so tests can assert probe count.
class _ScriptedLink extends Link {
  _ScriptedLink(this.outcomes);
  final List<Object> outcomes;
  int requests = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final outcome = outcomes[requests++];
    return outcome is Response ? Stream.value(outcome) : Stream.error(outcome);
  }
}

GraphQLClient _client(Link link) =>
    GraphQLClient(link: link, cache: GraphQLCache(store: InMemoryStore()));

// __typename is required: the client adds it to the query and the cache
// normalizer treats a response without it as partial data.
const _storeData = {
  '__typename': 'Query',
  'extensionStores': {'__typename': 'ExtensionStoreNodeList', 'totalCount': 1},
};
const _storeResponse = Response(response: {'data': _storeData}, data: _storeData);

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
  test('data present but no extensionStores key => transient', () {
    expect(classifyStoreProbe(_result(data: {'other': 1})), null);
  });
  test('GraphQL errors win over a simultaneous link exception', () {
    expect(
      classifyStoreProbe(_result(exception: OperationException(
        graphqlErrors: [const GraphQLError(message: 'Cannot query field "extensionStores" on type "Query"')],
        linkException: ServerException(originalException: Exception('also failed'), parsedResponse: null),
      ))),
      false,
    );
  });

  test('transient failure is not memoized: next call re-probes', () async {
    final link = _ScriptedLink([
      ServerException(originalException: Exception('timeout'), parsedResponse: null),
      _storeResponse,
    ]);
    final repository = ExtensionStoreRepository(_client(link));

    expect(await repository.supportsExtensionStores(), false);
    expect(await repository.supportsExtensionStores(), true);
    expect(link.requests, 2);
  });

  test('definitive verdict is memoized: one probe per client', () async {
    final link = _ScriptedLink([_storeResponse]);
    final repository = ExtensionStoreRepository(_client(link));

    expect(await repository.supportsExtensionStores(), true);
    expect(await repository.supportsExtensionStores(), true);
    expect(link.requests, 1);
  });
}
