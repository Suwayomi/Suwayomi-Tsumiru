import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_session_repository.dart';

class _Replies extends Link {
  _Replies(this.responses);
  final List<Response> responses;
  final operations = <String?>[];
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    operations.add(
      request.operation.document.definitions
          .whereType<OperationDefinitionNode>()
          .single
          .name
          ?.value,
    );
    yield responses.removeAt(0);
  }
}

void main() {
  Response data(Map<String, dynamic> value) =>
      Response(response: {}, data: {'__typename': 'Query', ...value});
  Response identity(String id) => data({
    'metas': {
      '__typename': 'MetaTypeConnection',
      'nodes': [
        {
          '__typename': 'GlobalMetaType',
          'key': 'tsumiru_server_instance_id',
          'value': id,
        },
      ],
    },
  });
  final user = {
    '__typename': 'UserType',
    'id': 2,
    'username': 'Canonical',
    'roles': ['USER'],
    'permissions': <String>[],
  };
  test(
    'binds canonical identity and only the authenticated metadata root',
    () async {
      final replies = _Replies([
        data({
          'user': {'id': 2, '__typename': 'UserType'},
        }),
        data({'user': user}),
        identity('user-2-root'),
      ]);
      final result = await AccountSessionRepository(
        GraphQLClient(link: replies, cache: GraphQLCache()),
      ).resolve(address: 'https://server:443', loginUsername: 'canonical');
      expect(result.userId, 2);
      expect(result.username, 'Canonical');
      expect(result.catalogId, 'user-2-root');
      expect(replies.operations, [
        'AccountCapability',
        'CurrentAccount',
        'OfflineServerIdentity',
      ]);
    },
  );
  test(
    'legacy validation uses shared identity without a current-user query',
    () async {
      final replies = _Replies([
        Response(
          response: {},
          errors: [
            const GraphQLError(
              message: 'Cannot query field "user" on type "Query".',
              extensions: {'classification': 'ValidationError'},
            ),
          ],
        ),
        identity('legacy-root'),
      ]);
      final result = await AccountSessionRepository(
        GraphQLClient(link: replies, cache: GraphQLCache()),
      ).resolve(address: 'https://server:443', loginUsername: 'legacy');
      expect(result.userId, isNull);
      expect(result.catalogId, 'legacy-root');
      expect(replies.operations, [
        'AccountCapability',
        'OfflineServerIdentity',
      ]);
    },
  );
  test(
    'unknown or unauthenticated account response never reads a catalog',
    () async {
      for (final response in [
        data({'user': null}),
        Response(
          response: {},
          errors: [const GraphQLError(message: 'Unauthorized')],
        ),
      ]) {
        final replies = _Replies([response]);
        await expectLater(
          AccountSessionRepository(
            GraphQLClient(link: replies, cache: GraphQLCache()),
          ).resolve(address: 'https://server:443', loginUsername: 'reader'),
          throwsStateError,
        );
        expect(replies.operations, ['AccountCapability']);
      }
    },
  );
  test('empty legacy username is rejected before metadata access', () async {
    final replies = _Replies([
      Response(
        response: {},
        errors: [
          const GraphQLError(
            message: 'Cannot query field "user" on type "Query".',
            extensions: {'classification': 'ValidationError'},
          ),
        ],
      ),
    ]);
    await expectLater(
      AccountSessionRepository(
        GraphQLClient(link: replies, cache: GraphQLCache()),
      ).resolve(address: 'https://server:443', loginUsername: ''),
      throwsArgumentError,
    );
    expect(replies.operations, ['AccountCapability']);
  });
  test('unsafe account metadata cannot become a directory', () async {
    final replies = _Replies([
      data({
        'user': {'id': 2, '__typename': 'UserType'},
      }),
      data({'user': user}),
      identity('../other'),
    ]);
    await expectLater(
      AccountSessionRepository(
        GraphQLClient(link: replies, cache: GraphQLCache()),
      ).resolve(address: 'https://server:443', loginUsername: 'reader'),
      throwsArgumentError,
    );
  });
}
