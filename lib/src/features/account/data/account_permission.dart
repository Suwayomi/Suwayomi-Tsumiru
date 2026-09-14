import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../domain/account_access.dart';
import 'account_providers.dart';

class AccountPermissionDenied implements Exception {
  const AccountPermissionDenied(this.permission);
  final Enum$UserPermission permission;

  @override
  String toString() => 'Forbidden';
}

class AccountPermissionGuard {
  const AccountPermissionGuard(this.access);
  final AccountAccess Function() access;

  void require(Enum$UserPermission permission) {
    if (!access().allows(permission)) {
      throw AccountPermissionDenied(permission);
    }
  }

  Future<T> run<T>(
    Enum$UserPermission permission,
    Future<T> Function() action,
  ) async {
    require(permission);
    return action();
  }
}

final accountPermissionGuardProvider = Provider<AccountPermissionGuard>(
  (ref) => AccountPermissionGuard(() => ref.read(settledAccountAccessProvider)),
);

class AccountPermissionUnavailable implements Exception {
  const AccountPermissionUnavailable();

  @override
  String toString() => 'Account permissions could not be verified';
}
