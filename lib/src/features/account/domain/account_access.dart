import 'package:graphql/client.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/misc/graphql_undefined_field.dart';
import '../data/graphql/__generated__/account.graphql.dart';

enum AccountCapability { supported, unsupported, unknown }

class AccountAccess {
  AccountAccess({required this.capability, Fragment$AccountDto? user})
    : user = user?.copyWith(
        permissions: List.unmodifiable(user.permissions),
        roles: List.unmodifiable(user.roles),
      );

  final AccountCapability capability;
  final Fragment$AccountDto? user;

  bool allows(Enum$UserPermission permission) => switch (capability) {
    AccountCapability.unsupported => true,
    AccountCapability.unknown => false,
    AccountCapability.supported =>
      canEditRoles || (user?.permissions.contains(permission) ?? false),
  };

  bool get canEditRoles =>
      capability == AccountCapability.supported &&
      (user?.roles.contains(Enum$UserRole.ADMIN) ?? false);

  bool get canManageUsers =>
      capability == AccountCapability.supported &&
      allows(Enum$UserPermission.MANAGE_USERS);
}

/// What in [result] a [classifyAccountResponse] of `unknown` rests on, for the
/// debug log: the link failure, the GraphQL error messages, or the user the
/// server answered with.
String describeAccountResponse(QueryResult<Query$AccountCapability> result) {
  final exception = result.exception;
  final link = exception?.linkException;
  if (link != null) {
    final original = link.originalException;
    return 'link=${link.runtimeType}'
        '${original == null ? '' : ' cause=${original.runtimeType}: $original'}';
  }
  final errors = exception?.graphqlErrors ?? const <GraphQLError>[];
  if (errors.isNotEmpty) {
    return 'graphql=${errors.map((e) => e.message).toList()}'
        '${result.data == null ? '' : ' with-data'}';
  }
  return 'user=${result.data?['user']}';
}

AccountCapability classifyAccountResponse(
  QueryResult<Query$AccountCapability> result,
) {
  final exception = result.exception;
  if (exception != null) {
    if (exception.linkException != null || result.data != null) {
      return AccountCapability.unknown;
    }
    final errors = exception.graphqlErrors;
    return errors.isNotEmpty &&
            errors.every(
              (e) => isUndefinedFieldError(e, type: 'Query', field: 'user'),
            )
        ? AccountCapability.unsupported
        : AccountCapability.unknown;
  }
  final user = result.data?['user'];
  final id = user is Map<String, dynamic> ? user['id'] : null;
  return id is int && id > 0
      ? AccountCapability.supported
      : AccountCapability.unknown;
}
