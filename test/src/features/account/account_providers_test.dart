import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

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
  Future<AccountCapability> capability({bool Function()? stillWanted}) async {
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

void main() {
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

}
