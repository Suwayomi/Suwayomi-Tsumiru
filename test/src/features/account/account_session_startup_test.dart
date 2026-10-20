import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_session_startup.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/notifications/controller/notifications_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'account_providers_test.dart' show FakeAccountRepository;

final _offlineProvider = NotifierProvider<_OfflineToggle, bool>(
  _OfflineToggle.new,
);

class _OfflineToggle extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool active) => state = active;
}

final _accessProvider = NotifierProvider<_Access, AccountAccess>(_Access.new);

class _Access extends Notifier<AccountAccess> {
  @override
  AccountAccess build() => AccountAccess(capability: AccountCapability.unknown);
  void set(AccountAccess access) => state = access;
}

class StartupCredentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

class StartupEndpoint extends ServerEndpointResolver {
  @override
  String? build() => 'http://server';
}

class StartupNotifications extends NotificationsController {
  StartupNotifications(super.ref, this.onSync);
  final Future<void> Function() onSync;
  @override
  Future<void> sync() => onSync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> setup({
    required Future<String> Function() verify,
    required Future<void> Function() notify,
    AuthType mode = AuthType.none,
    Future<AccountAccess> Function()? refresh,
    FakeAccountRepository? repository,
  }) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authTypeKeyProvider.overrideWithValue(mode),
        if (mode != AuthType.uiLogin)
          settledAccountAccessProvider.overrideWith(
            (ref) => ref.watch(_accessProvider),
          ),
        if (repository != null)
          accountRepositoryProvider.overrideWithValue(repository),
        refreshAccountAccessProvider.overrideWithValue(
          refresh ??
              () async =>
                  AccountAccess(capability: AccountCapability.unsupported),
        ),
        authCredentialsStoreProvider.overrideWith(StartupCredentials.new),
        serverEndpointResolverProvider.overrideWith(StartupEndpoint.new),
        currentServerAddressProvider.overrideWithValue('http://server'),
        verifiedServerInstanceIdProvider.overrideWith((ref) => verify()),
        offlineActiveProvider.overrideWith(
          (ref) => ref.watch(_offlineProvider),
        ),
        notificationsControllerProvider.overrideWith(
          (ref) => StartupNotifications(ref, notify),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    return container;
  }

  test(
    'verification completing after an identity change starts no old-account work',
    () async {
      final verified = Completer<String>();
      var notifications = 0;
      final container = await setup(
        verify: () => verified.future,
        notify: () async => notifications++,
      );
      final startup = AccountSessionStartup(container);
      addTearDown(startup.dispose);
      final work = startup.start();
      await Future<void>.delayed(Duration.zero);
      await container
          .read(authCredentialsStoreProvider.notifier)
          .withIdentityChange(() async {});
      verified.complete('catalog-a');
      await work;
      expect(notifications, 0);
    },
  );

}
