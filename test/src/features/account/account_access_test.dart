import 'dart:convert';
import 'dart:io';

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
  test('users receive only their grants', () {
    final access = AccountAccess(
      capability: AccountCapability.supported,
      user: account(permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS]),
    );
    expect(access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isTrue);
    expect(access.allows(Enum$UserPermission.MANAGE_SETTINGS), isFalse);
    expect(access.canManageUsers, isFalse);
  });
  test('admins can manage users and roles without individual grants', () {
    final access = AccountAccess(
      capability: AccountCapability.supported,
      user: account(roles: [Enum$UserRole.ADMIN]),
    );
    expect(access.allows(Enum$UserPermission.MANAGE_SETTINGS), isTrue);
    expect(access.canManageUsers, isTrue);
    expect(access.canEditRoles, isTrue);
  });
  test('user managers cannot edit roles', () {
    final access = AccountAccess(
      capability: AccountCapability.supported,
      user: account(permissions: [Enum$UserPermission.MANAGE_USERS]),
    );
    expect(access.canManageUsers, isTrue);
    expect(access.canEditRoles, isFalse);
  });
  test('unknown capability does not trust stored grants', () {
    final access = AccountAccess(
      capability: AccountCapability.unknown,
      user: account(roles: [Enum$UserRole.ADMIN]),
    );
    expect(access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isFalse);
    expect(access.canManageUsers, isFalse);
    expect(access.canEditRoles, isFalse);
  });
  test(
    'legacy servers retain actions but do not expose account management',
    () {
      final access = AccountAccess(capability: AccountCapability.unsupported);
      expect(access.allows(Enum$UserPermission.MANAGE_SETTINGS), isTrue);
      expect(access.canManageUsers, isFalse);
      expect(access.canEditRoles, isFalse);
    },
  );
  test('missing accounts and visitors receive no implicit grants', () {
    final missing = AccountAccess(capability: AccountCapability.supported);
    final visitor = AccountAccess(
      capability: AccountCapability.supported,
      user: account(roles: [Enum$UserRole.VISITOR]),
    );
    expect(missing.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isFalse);
    expect(visitor.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS), isFalse);
  });
  test('account grants are immutable snapshots', () {
    final grants = [Enum$UserPermission.DOWNLOAD_CHAPTERS];
    final access = AccountAccess(
      capability: AccountCapability.supported,
      user: account(permissions: grants),
    );
    grants.add(Enum$UserPermission.MANAGE_SETTINGS);
    expect(access.allows(Enum$UserPermission.MANAGE_SETTINGS), isFalse);
  });
  test('valid authenticated payload establishes support', () {
    expect(
      classifyAccountResponse(
        response(
          data: {
            'user': {'id': 2},
          },
        ),
      ),
      AccountCapability.supported,
    );
  });
  test('missing or malformed account payload remains unknown', () {
    for (final data in <Map<String, dynamic>?>[
      null,
      {},
      {'user': null},
      {
        'user': {'id': '2'},
      },
      Query$CurrentAccount(user: account().copyWith(id: 0)).toJson(),
    ]) {
      expect(
        classifyAccountResponse(response(data: data)),
        AccountCapability.unknown,
      );
    }
  });
  test('both validation formats establish legacy support', () {
    for (final error in [
      missingUser,
      const GraphQLError(
        message: 'Cannot query field "user" on type "Query".',
        extensions: {'code': 'GRAPHQL_VALIDATION_FAILED'},
      ),
      // What a pre-accounts Suwayomi actually sends: the validation message
      // with empty extensions. Demanding a classification here denied every
      // permission and broke UI Login sign-in against those servers.
      const GraphQLError(
        message:
            "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined",
        extensions: {},
      ),
      const GraphQLError(message: 'Cannot query field "user" on type "Query".'),
    ]) {
      expect(
        classifyAccountResponse(response(errors: [error])),
        AccountCapability.unsupported,
      );
    }
  });
  test('auth, execution, nested-field, and mixed errors remain unknown', () {
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
  test('partial account and network failures remain unknown', () {
    final data = Query$CurrentAccount(user: account()).toJson();
    expect(
      classifyAccountResponse(response(data: data, errors: [missingUser])),
      AccountCapability.unknown,
    );
    expect(
      classifyAccountResponse(
        response(
          errors: [missingUser],
          linkException: UnknownException('offline', StackTrace.current),
        ),
      ),
      AccountCapability.unknown,
    );
  });
  test('actual legacy schema validation classifies the minimal probe', () {
    final fixture =
        jsonDecode(
              File(
                'test/src/features/account/fixtures/legacy_capability_error.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final errors = (fixture['errors'] as List)
        .map(
          (error) => GraphQLError(
            message: error['message'] as String,
            extensions: Map<String, dynamic>.from(error['extensions'] as Map),
          ),
        )
        .toList();
    expect(errors, hasLength(1));
    expect(
      classifyAccountResponse(response(errors: errors)),
      AccountCapability.unsupported,
    );
  });

  group('describeAccountResponse (debug log for an unknown capability)', () {
    test('names the link failure and its cause', () {
      final text = describeAccountResponse(
        response(
          linkException: ServerException(
            originalException: const SocketException('unreachable'),
          ),
        ),
      );
      expect(text, contains('link=ServerException'));
      expect(text, contains('cause=SocketException'));
    });

    test('lists the GraphQL error messages', () {
      final text = describeAccountResponse(
        response(errors: [const GraphQLError(message: 'Unauthorized')]),
      );
      expect(text, 'graphql=[Unauthorized]');
    });

    test('shows the user the server answered with', () {
      expect(
        describeAccountResponse(response(data: {'user': null})),
        'user=null',
      );
    });
  });
}
