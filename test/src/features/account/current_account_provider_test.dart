import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

Fragment$AccountDto _user(int id) => Fragment$AccountDto(
  id: id,
  username: 'reader-$id',
  permissions: [Enum$UserPermission.MANAGE_USERS],
  roles: [Enum$UserRole.ADMIN],
);
AccountBinding _binding(int id) => AccountBinding(
  address: 'http://server',
  userId: id,
  username: 'reader-$id',
  catalogId: 'catalog-$id',
);
String _cached(int id) =>
    jsonEncode({'catalogId': 'catalog-$id', 'user': _user(id).toJson()});

class _Repository extends AccountRepository {
  _Repository()
    : super(
        GraphQLClient(
          cache: GraphQLCache(),
          link: Link.function((request, [forward]) => const Stream.empty()),
        ),
      );
  Future<Fragment$AccountDto?> Function() lookup = () async => _user(1);
  @override
  Future<AccountCapability> capability({bool Function()? stillWanted}) async =>
      AccountCapability.supported;
  @override
  Future<Fragment$AccountDto?> current() => lookup();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late SharedPreferences preferences;
  late _Repository repository;

  Future<void> setup({
    Map<String, Object> cache = const {},
    bool offline = false,
  }) async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A-access',
      'auth.ui.refreshToken': 'A-refresh',
      'auth.ui.accountBinding': _binding(
        1,
      ).encode(accessToken: 'A-access', refreshToken: 'A-refresh'),
    });
    SharedPreferences.setMockInitialValues(cache);
    preferences = await SharedPreferences.getInstance();
    repository = _Repository();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        accountRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    container.read(serverUnreachableProvider.notifier).set(offline);
  }

  test(
    'offline display restores verified cached profile without granting permissions',
    () async {
      await setup(
        cache: {'account.current/catalog-1': _cached(1)},
        offline: true,
      );
      await container.read(accountAccessProvider.future);
      expect(container.read(currentAccountProvider)?.username, 'reader-1');
      expect(
        container.read(settledAccountAccessProvider).capability,
        AccountCapability.unknown,
      );
      expect(
        container.read(settledAccountAccessProvider).canManageUsers,
        isFalse,
      );
    },
  );

}
