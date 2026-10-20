import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class RecordingLink extends Link {
  RecordingLink(this.response);
  final Response response;
  late Request recorded;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    recorded = request;
    yield response;
  }
}

void main() {
  late RecordingLink link;
  AccountRepository repository(Response response) {
    link = RecordingLink(response);
    return AccountRepository(
      GraphQLClient(link: link, cache: GraphQLCache()),
      access: () => AccountAccess(
        capability: AccountCapability.supported,
        user: Fragment$AccountDto(
          id: 9,
          username: 'manager',
          roles: [Enum$UserRole.USER],
          permissions: [Enum$UserPermission.MANAGE_USERS],
        ),
      ),
    );
  }

  test(
    'capability uses a fragment-free query compatible with legacy validation',
    () async {
      final repo = repository(
        Response(
          response: {},
          errors: [
            const GraphQLError(
              message:
                  "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
              extensions: {'classification': 'ValidationError'},
            ),
          ],
        ),
      );
      expect(await repo.capability(), AccountCapability.unsupported);
      expect(
        link.recorded.operation.document.definitions
            .whereType<FragmentDefinitionNode>(),
        isEmpty,
      );
      expect(
        printNode(link.recorded.operation.document),
        isNot(contains('UserType')),
      );
    },
  );

}
