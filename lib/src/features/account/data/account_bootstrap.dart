import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_coordinator.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../offline/data/offline_runtime_storage.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'account_session_storage.dart';

Future<void> restoreAccountSession(ProviderContainer container) async {
  final store = container.read(authCredentialsStoreProvider.notifier);
  final current = store.captureSession();
  final address = container.read(currentServerAddressProvider);
  final epoch = store.serverEpoch;
  final credentials = await container.read(authCredentialsStoreProvider.future);
  void checkSession() {
    if (!current() ||
        container.read(currentServerAddressProvider) != address ||
        store.serverEpoch != epoch) {
      throw StateError('Authentication session changed during startup');
    }
  }

  checkSession();
  if (container.read(authTypeKeyProvider) == AuthType.uiLogin &&
      credentials.accountBinding == null &&
      store.uiLoginTokens() != null) {
    final client = container.read(unauthenticatedGraphQlClientProvider);
    final coordinator = container.read(authCoordinatorProvider.notifier);
    final username = container.read(authUsernameProvider) ?? '';
    final password = credentials.password;
    final expiry = credentials.uiAccessTokenExpiresAt;
    if (expiry != null && !expiry.isAfter(DateTime.now())) {
      final outcome = await coordinator.refreshUiAccessToken(
        gqlClient: client,
        trigger: 'account-bootstrap',
      );
      checkSession();
      if (outcome is! RefreshSuccess) {
        throw StateError('Account credentials could not be refreshed');
      }
    }
    checkSession();
    final tokens = store.uiLoginTokens();
    if (tokens == null) {
      throw StateError('Account credentials are unavailable');
    }
    await coordinator.adoptUiLoginTokens(
      gqlClient: client,
      tokens: tokens,
      forEpoch: epoch,
      address: address,
      username: username,
      password: password,
    );
    if (store.sessionChanging ||
        store.uiLoginTokens()?.accessToken != tokens.accessToken ||
        container.read(currentServerAddressProvider) != address) {
      throw StateError('Authentication session changed during startup');
    }
    if (container.read(offlineRuntimeStorageProvider) != null) return;
  }
  await container.read(accountSessionStorageProvider).restore();
}
