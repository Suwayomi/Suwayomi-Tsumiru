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

class FakeAccountRepository extends AccountRepository {
  FakeAccountRepository({
    this.support = AccountCapability.supported,
    this.user,
    this.error,
  }) : super(
         GraphQLClient(
           link: Link.function((request, [forward]) => const Stream.empty()),
           cache: GraphQLCache(),
         ),
       );
  AccountCapability support;
  final Fragment$AccountDto? user;
  final Object? error;
  int probes = 0;
  int currentCalls = 0;

  @override
  Future<AccountCapability> capability() async {
    probes++;
    return support;
  }

  @override
  Future<Fragment$AccountDto?> current() async {
    currentCalls++;
    if (error != null) throw error!;
    return user;
  }
}

class _Credentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

class _SignedInCredentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState(
    uiAccessToken: 'access',
    uiRefreshToken: 'refresh',
    accountBinding: AccountBinding(
      address: 'http://server',
      userId: 2,
      username: 'admin',
      catalogId: 'A',
    ),
  );
}

void main() {
  final admin = Fragment$AccountDto(
    id: 2,
    username: 'admin',
    permissions: [],
    roles: [Enum$UserRole.ADMIN],
  );
  ProviderContainer container(
    FakeAccountRepository repository, {
    AuthType? authType = AuthType.uiLogin,
  }) {
    final value = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        authTypeKeyProvider.overrideWithValue(authType),
        authCredentialsStoreProvider.overrideWith(_Credentials.new),
        accountRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(value.dispose);
    return value;
  }

  test('non-account auth modes never query account APIs', () async {
    for (final mode in [
      AuthType.none,
      AuthType.basic,
      AuthType.simpleLogin,
      null,
    ]) {
      final repository = FakeAccountRepository();
      final access = await container(
        repository,
        authType: mode,
      ).read(accountAccessProvider.future);
      expect(access.capability, AccountCapability.unsupported);
      expect(repository.probes, 0);
      expect(repository.currentCalls, 0);
    }
  });

  test('unsupported capability skips current user', () async {
    final repository = FakeAccountRepository(
      support: AccountCapability.unsupported,
    );
    final access = await container(
      repository,
    ).read(accountAccessProvider.future);
    expect(access.capability, AccountCapability.unsupported);
    expect(repository.currentCalls, 0);
  });

  test('unknown capability is retryable and exposes no grants', () async {
    final repository = FakeAccountRepository(
      support: AccountCapability.unknown,
    );
    final scope = container(repository);
    await expectLater(
      scope.read(accountAccessProvider.future),
      throwsStateError,
    );
    expect(
      scope.read(settledAccountAccessProvider).capability,
      AccountCapability.unknown,
    );
    expect(repository.currentCalls, 0);
  });

  test('supported accounts expose actual user grants', () async {
    final access = await container(
      FakeAccountRepository(user: admin),
    ).read(accountAccessProvider.future);
    expect(access.capability, AccountCapability.supported);
    expect(access.user?.id, 2);
    expect(access.canEditRoles, isTrue);
  });

  test('missing or invalid current account remains unknown', () async {
    for (final user in [
      null,
      admin.copyWith(id: 0),
      admin.copyWith(username: ''),
    ]) {
      final scope = container(FakeAccountRepository(user: user));
      await expectLater(
        scope.read(accountAccessProvider.future),
        throwsStateError,
      );
      expect(
        scope.read(settledAccountAccessProvider).capability,
        AccountCapability.unknown,
      );
      expect(scope.read(settledAccountAccessProvider).canEditRoles, isFalse);
    }
  });

  test('current account errors propagate', () async {
    await expectLater(
      container(
        FakeAccountRepository(error: StateError('unauthorized')),
      ).read(accountAccessProvider.future),
      throwsStateError,
    );
  });

  test('network recovery retries unknown account capability', () async {
    final repository = FakeAccountRepository(
      support: AccountCapability.unknown,
      user: admin,
    );
    final scope = container(repository);
    await scope.read(authCredentialsStoreProvider.future);
    await expectLater(
      scope.read(accountAccessProvider.future),
      throwsStateError,
    );
    scope.read(serverUnreachableProvider.notifier).set(true);
    repository.support = AccountCapability.supported;
    scope.read(serverUnreachableProvider.notifier).set(false);
    expect(
      (await scope.read(accountAccessProvider.future)).canEditRoles,
      isTrue,
    );
  });

  test(
    'refreshing grants exposes unknown until the next query completes',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final scope = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
          authCredentialsStoreProvider.overrideWith(_SignedInCredentials.new),
          accountRepositoryProvider.overrideWithValue(
            FakeAccountRepository(user: admin),
          ),
        ],
      );
      addTearDown(scope.dispose);
      await scope.read(authCredentialsStoreProvider.future);
      await scope.read(accountAccessProvider.future);
      expect(scope.read(settledAccountAccessProvider).canEditRoles, isTrue);
      scope.invalidate(accountAccessProvider);
      expect(
        scope.read(settledAccountAccessProvider).capability,
        AccountCapability.unknown,
      );
      await scope.read(accountAccessProvider.future);
      expect(scope.read(settledAccountAccessProvider).canEditRoles, isTrue);
    },
  );

  test('repository replacement replaces the previous grants', () async {
    final first = FakeAccountRepository(user: admin);
    final second = FakeAccountRepository(
      user: admin.copyWith(
        id: 3,
        username: 'reader',
        roles: [Enum$UserRole.USER],
      ),
    );
    final scope = container(first);
    expect(
      (await scope.read(accountAccessProvider.future)).canEditRoles,
      isTrue,
    );
    scope.updateOverrides([
      authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
      authCredentialsStoreProvider.overrideWith(_Credentials.new),
      accountRepositoryProvider.overrideWithValue(second),
    ]);
    final access = await scope.read(accountAccessProvider.future);
    expect(access.user?.id, 3);
    expect(access.canEditRoles, isFalse);
  });
}
