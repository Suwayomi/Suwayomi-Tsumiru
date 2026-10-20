import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

Fragment$AccountDto account({
  List<Enum$UserRole> roles = const [Enum$UserRole.USER],
  List<Enum$UserPermission> permissions = const [],
}) => Fragment$AccountDto(
  id: 2,
  username: 'reader',
  permissions: permissions,
  roles: roles,
);

QueryResult<Query$AccountCapability> response({
  Map<String, dynamic>? data,
  List<GraphQLError> errors = const [],
  LinkException? linkException,
}) => QueryResult(
  options: Options$Query$AccountCapability(),
  source: QueryResultSource.network,
  data: data,
  exception: errors.isEmpty && linkException == null
      ? null
      : OperationException(graphqlErrors: errors, linkException: linkException),
);

const missingUser = GraphQLError(
  message:
      "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
  extensions: {'classification': 'ValidationError'},
);

void main() {
  test('permission grants, unknown capability and error classification', () {
    final user = AccountAccess(
      capability: AccountCapability.supported,
      user: account(permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS]),
    );
    expect(user.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isTrue);
    expect(user.allows(Enum$UserPermission.MANAGE_SETTINGS), isFalse);
    expect(user.canManageUsers, isFalse);

    final admin = AccountAccess(
      capability: AccountCapability.supported,
      user: account(roles: [Enum$UserRole.ADMIN]),
    );
    expect(admin.allows(Enum$UserPermission.MANAGE_SETTINGS), isTrue);
    expect(admin.canManageUsers, isTrue);
    expect(admin.canEditRoles, isTrue);

    final manager = AccountAccess(
      capability: AccountCapability.supported,
      user: account(permissions: [Enum$UserPermission.MANAGE_USERS]),
    );
    expect(manager.canManageUsers, isTrue);
    expect(manager.canEditRoles, isFalse);

    final unknown = AccountAccess(
      capability: AccountCapability.unknown,
      user: account(roles: [Enum$UserRole.ADMIN]),
    );
    expect(unknown.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isFalse);
    expect(unknown.canManageUsers, isFalse);
    expect(unknown.canEditRoles, isFalse);

    // Legacy servers retain actions but do not expose account management.
    final legacy = AccountAccess(capability: AccountCapability.unsupported);
    expect(legacy.allows(Enum$UserPermission.MANAGE_SETTINGS), isTrue);
    expect(legacy.canManageUsers, isFalse);
    expect(legacy.canEditRoles, isFalse);

    // Auth, execution, nested-field and mixed errors all remain unknown.
    for (final errors in [
      [const GraphQLError(message: 'Unauthorized')],
      [
        const GraphQLError(
          message: 'Cannot query field "username" on type "UserType".',
          extensions: {'code': 'GRAPHQL_VALIDATION_FAILED'},
        ),
      ],
      [missingUser, const GraphQLError(message: 'Internal server error')],
      [
        const GraphQLError(
          message: 'Cannot query field "user" on type "Query". Database failed',
          extensions: {'code': 'GRAPHQL_VALIDATION_FAILED'},
        ),
      ],
      // A classification that contradicts "field undefined" still rules it out.
      [
        const GraphQLError(
          message:
              "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
          extensions: {'classification': 'DataFetchingException'},
        ),
      ],
    ]) {
      expect(
        classifyAccountResponse(response(errors: errors)),
        AccountCapability.unknown,
      );
    }
  });

  group('describeAccountResponse (debug log for an unknown capability)', () {});
}
