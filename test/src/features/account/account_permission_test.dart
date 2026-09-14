import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';

void main() {
  const permission = Enum$UserPermission.MANAGE_SETTINGS;
  test('unknown and denied accounts cannot issue a mutation', () async {
    for (final access in [
      AccountAccess(capability: AccountCapability.unknown),
      AccountAccess(
        capability: AccountCapability.supported,
        user: Fragment$AccountDto(
          id: 2,
          username: 'reader',
          permissions: [],
          roles: [Enum$UserRole.USER],
        ),
      ),
    ]) {
      var mutations = 0;
      await expectLater(
        AccountPermissionGuard(() => access).run(permission, () async {
          mutations++;
        }),
        throwsA(isA<AccountPermissionDenied>()),
      );
      expect(mutations, 0);
    }
  });

  test('legacy and admin accounts may issue the operation', () async {
    for (final access in [
      AccountAccess(capability: AccountCapability.unsupported),
      AccountAccess(
        capability: AccountCapability.supported,
        user: Fragment$AccountDto(
          id: 1,
          username: 'admin',
          permissions: [],
          roles: [Enum$UserRole.ADMIN],
        ),
      ),
    ]) {
      expect(
        await AccountPermissionGuard(
          () => access,
        ).run(permission, () async => 7),
        7,
      );
    }
  });

  test(
    'permission errors keep their classification through GraphQL wrappers',
    () {
      final exception = OperationException(
        graphqlErrors: [
          const GraphQLError(
            message:
                'Exception while fetching data (/users) : Forbidden\r\n\r\n'
                'suwayomi.tachidesk.server.user.ForbiddenException: Forbidden\n'
                '\tat server.UserTypeKt.requirePermissions(UserType.kt:73)',
          ),
        ],
      );
      expect(isPermissionDenied(exception), isTrue);
      expect(isPermissionDenied(OperationMessageException(exception)), isTrue);
      expect(
        isPermissionDenied(const AccountPermissionDenied(permission)),
        isTrue,
      );
      expect(isPermissionDenied('Forbidden, Forbidden'), isTrue);
      expect(isPermissionDenied('Unauthorized'), isFalse);
      expect(
        isPermissionDenied(StateError('Server forbidden by proxy')),
        isFalse,
      );
      expect(
        isPermissionDenied(const ServerNotJsonException(403, 'Forbidden')),
        isFalse,
      );
    },
  );
}
