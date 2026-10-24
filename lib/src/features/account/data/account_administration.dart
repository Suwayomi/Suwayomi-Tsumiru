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

final accountManagementUsersProvider =
    FutureProvider.autoDispose<List<Fragment$AccountDto>>((ref) async {
      final repository = ref.watch(accountRepositoryProvider);
      final users = <Fragment$AccountDto>[];
      int? after;
      do {
        final page = await repository.users(first: 25, after: after);
        if (page == null) throw StateError('Missing users response');
        users.addAll(page.nodes);
        if (!page.pageInfo.hasNextPage) return users;
        final next = page.pageInfo.endCursor;
        if (next == null || next == after) {
          throw StateError('Missing next users page');
        }
        after = next;
      } while (true);
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

final accountCreationPermissionsProvider = FutureProvider((ref) async {
  if (!ref.watch(settledAccountAccessProvider).canManageUsers) {
    return (registration: false, user: false, codes: false);
  }
  return ref.watch(accountRepositoryProvider).creationPermissionCapability();
});

final accountCodePermissionsProvider = FutureProvider.autoDispose((ref) async {
  final repository = ref.watch(accountRepositoryProvider);
  final capability = await ref.watch(accountCreationPermissionsProvider.future);
  if (!capability.codes) return <int, List<Enum$UserPermission>?>{};
  return repository.codePermissions();
});

const defaultAccountPermissions = {
  Enum$UserPermission.DOWNLOAD_CHAPTERS,
  Enum$UserPermission.INSTALL_EXTENSIONS,
  Enum$UserPermission.INSTALL_EXTERNAL_EXTENSIONS,
  Enum$UserPermission.UNINSTALL_EXTENSIONS,
};
