import 'package:graphql/client.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
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

AccountCapability classifyAccountResponse(
  QueryResult<Query$AccountCapability> result,
) {
  final exception = result.exception;
  if (exception != null) {
    if (exception.linkException != null || result.data != null) {
      return AccountCapability.unknown;
    }
    final errors = exception.graphqlErrors;
    return errors.isNotEmpty && errors.every(_missingUserField)
        ? AccountCapability.unsupported
        : AccountCapability.unknown;
  }
  final user = result.data?['user'];
  final id = user is Map<String, dynamic> ? user['id'] : null;
  return id is int && id > 0
      ? AccountCapability.supported
      : AccountCapability.unknown;
}

bool _missingUserField(GraphQLError error) {
  final extensions = error.extensions;
  if (extensions?['classification'] != 'ValidationError' &&
      extensions?['code'] != 'GRAPHQL_VALIDATION_FAILED') {
    return false;
  }
  return error.message == 'Cannot query field "user" on type "Query".' ||
      error.message == "Cannot query field 'user' on type 'Query'." ||
      error.message ==
          "Validation error (FieldUndefined@[user]) : Field 'user' in type 'Query' is undefined";
}
