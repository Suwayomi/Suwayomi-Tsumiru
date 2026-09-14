import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import 'account_permission.dart';
import 'account_providers.dart';
import 'graphql/__generated__/account.graphql.dart';

typedef AccountPage = ({String search, int? after});

final accountUsersProvider = FutureProvider.autoDispose
    .family<Query$Accounts$users, AccountPage>((ref, page) async {
      if (!ref.watch(settledAccountAccessProvider).canManageUsers) {
        throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_USERS);
      }
      final result = await ref
          .watch(accountRepositoryProvider)
          .users(first: 25, after: page.after, search: page.search);
      if (result == null) throw StateError('Missing users response');
      return result;
    });

final accountCodesProvider =
    FutureProvider.autoDispose<List<Fragment$AccountCodeDto>>((ref) async {
      if (!ref.watch(settledAccountAccessProvider).canManageUsers) {
        throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_USERS);
      }
      final result = await ref.watch(accountRepositoryProvider).codes();
      if (result == null) throw StateError('Missing codes response');
      return result;
    });

Input$UpdateUserInput accountPermissionUpdate({
  required int userId,
  required List<Enum$UserPermission> permissions,
  required bool canEditRoles,
  required Enum$UserRole role,
}) => Input$UpdateUserInput(
  userId: userId,
  permissions: permissions,
  role: canEditRoles ? role : null,
);
