import 'package:graphql/client.dart';

import '../../offline/data/account_storage_paths.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../domain/account_access.dart';
import '../domain/account_binding.dart';
import 'account_repository.dart';

class AccountSessionRepository {
  const AccountSessionRepository(this.client);

  final GraphQLClient client;

  Future<AccountBinding> resolve({
    required String address,
    required String loginUsername,
  }) async {
    final accounts = AccountRepository(client);
    final capability = await accounts.capability();
    if (capability == AccountCapability.unknown) {
      throw StateError('Could not verify account support');
    }
    final user = capability == AccountCapability.supported
        ? await accounts.current()
        : null;
    if (capability == AccountCapability.supported &&
        (user == null || user.id <= 0 || user.username.isEmpty)) {
      throw StateError('Could not verify the signed-in account');
    }
    if (user == null && loginUsername.isEmpty) {
      throw ArgumentError.value(loginUsername, 'loginUsername');
    }
    final catalogId = await OfflineServerIdentityRepository(client).resolve();
    accountStoragePath('', catalogId);
    return AccountBinding(
      address: address,
      userId: user?.id,
      username: user?.username ?? loginUsername,
      catalogId: catalogId,
    );
  }
}
