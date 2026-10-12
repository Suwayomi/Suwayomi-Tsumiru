import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_session_startup.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/notifications/controller/notifications_controller.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../helpers/fake_page_store.dart';
import '../../../helpers/offline_test_db.dart';
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

const _resumeBinding = AccountBinding(
  address: 'http://server',
  userId: 2,
  username: 'reader',
  catalogId: 'A',
);

class _ResumeCredentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState(
    accountBinding: _resumeBinding,
    uiAccessToken: 'access',
    uiRefreshToken: 'refresh',
  );
}

GraphQLClient _inertClient() => GraphQLClient(
  link: Link.function((request, [forward]) => const Stream.empty()),
  cache: GraphQLCache(),
);

/// Records whether the launch path drove the resume pump, so the test can
/// prove `_resume()` ran to completion instead of bailing at its permission
/// gate.
class _SpyCoordinator extends OfflineDownloadCoordinator {
  _SpyCoordinator({required super.db, required super.store})
    : super(
        resolvePages: (_) async => const [],
        engine: ChapterDownloadEngine(
          fetchPage: (_) async => throw UnimplementedError(),
          writePage: store,
          refreshAuth: () async => false,
        ),
      );
  final pumped = Completer<void>();
  @override
  Future<void> pumpDownloads() async {
    if (!pumped.isCompleted) pumped.complete();
    return super.pumpDownloads();
  }
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
    'signed-out UI login starts no verification, notifications or permission refresh',
    () async {
      var verifications = 0;
      var notifications = 0;
      var refreshes = 0;
      final repository = FakeAccountRepository();
      final container = await setup(
        mode: AuthType.uiLogin,
        repository: repository,
        verify: () async {
          verifications++;
          return 'A';
        },
        notify: () async {
          notifications++;
        },
        refresh: () async {
          refreshes++;
          return AccountAccess(capability: AccountCapability.unknown);
        },
      );
      final startup = AccountSessionStartup(container);
      addTearDown(startup.dispose);
      await startup.start();
      container.read(serverUnreachableProvider.notifier).set(true);
      container.read(serverUnreachableProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(verifications, 0);
      expect(notifications, 0);
      expect(refreshes, 0);
      expect(repository.probes, 0);
      expect(repository.currentCalls, 0);
    },
  );

  test('restoring download permission requests startup work again', () async {
    var verifications = 0;
    var notifications = 0;
    final resumed = Completer<void>();
    final container = await setup(
      verify: () async {
        verifications++;
        return 'A';
      },
      notify: () async {
        if (++notifications == 2) resumed.complete();
      },
    );
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    container
        .read(_accessProvider.notifier)
        .set(AccountAccess(capability: AccountCapability.supported));
    await Future<void>.delayed(Duration.zero);
    container
        .read(_accessProvider.notifier)
        .set(
          AccountAccess(
            capability: AccountCapability.supported,
            user: Fragment$AccountDto(
              id: 2,
              username: 'reader',
              roles: [],
              permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS],
            ),
          ),
        );
    await resumed.future;
    expect(verifications, 2);
    expect(notifications, 2);
  });

  test('worker-only denial resumes once after a fresh grant', () async {
    await preferences.setString(DBKeys.offlineCatalogServerId.name, 'A');
    var verifications = 0;
    var notifications = 0;
    final resumed = Completer<void>();
    final container = await setup(
      verify: () async {
        verifications++;
        return 'A';
      },
      notify: () async {
        if (++notifications == 2) resumed.complete();
      },
    );
    AccountAccess granted() => AccountAccess(
      capability: AccountCapability.supported,
      user: Fragment$AccountDto(
        id: 2,
        username: 'reader',
        roles: [],
        permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS],
      ),
    );
    container.read(_accessProvider.notifier).set(granted());
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    await preferences.setString(
      'offline.downloadPermission/A',
      '{"paused":false,"denialRevision":1}',
    );
    container.read(_accessProvider.notifier).set(granted());
    await resumed.future.timeout(const Duration(seconds: 2));
    container.read(_accessProvider.notifier).set(granted());
    await Future<void>.delayed(Duration.zero);
    expect(verifications, 2);
    expect(notifications, 2);
  });

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

  test('reconnect retries verification after an offline launch', () async {
    var verifications = 0;
    var notifications = 0;
    final synced = Completer<void>();
    final container = await setup(
      verify: () async {
        if (++verifications == 1) throw const SocketException('offline');
        return 'catalog-a';
      },
      notify: () async {
        notifications++;
        synced.complete();
      },
    );
    container.read(serverUnreachableProvider.notifier).set(true);
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    expect(notifications, 0);
    container.read(serverUnreachableProvider.notifier).set(false);
    await synced.future;
    expect(verifications, 2);
    expect(notifications, 1);
  });

  test(
    'dispose removes reconnect listeners and stops a delayed continuation',
    () async {
      final pending = Completer<void>();
      final entered = Completer<void>();
      var verifications = 0;
      final container = await setup(
        verify: () async {
          verifications++;
          return 'catalog-a';
        },
        notify: () {
          entered.complete();
          return pending.future;
        },
      );
      final startup = AccountSessionStartup(container);
      final work = startup.start();
      await entered.future;
      startup.dispose();
      container.read(serverUnreachableProvider.notifier).set(true);
      container.read(serverUnreachableProvider.notifier).set(false);
      container.dispose();
      pending.complete();
      await work;
      expect(verifications, 1);
    },
  );

  test('a stale settled snapshot cannot skip resumed launch work', () async {
    final db = testOfflineDatabase();
    addTearDown(db.close);
    final store = FakePageStore();
    final coordinator = _SpyCoordinator(db: db, store: store);
    final repository = FakeAccountRepository(
      user: Fragment$AccountDto(
        id: 2,
        username: 'reader',
        roles: [],
        permissions: [Enum$UserPermission.DOWNLOAD_CHAPTERS],
      ),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        authCredentialsStoreProvider.overrideWith(_ResumeCredentials.new),
        accountRepositoryProvider.overrideWithValue(repository),
        serverEndpointResolverProvider.overrideWith(StartupEndpoint.new),
        currentServerAddressProvider.overrideWithValue('http://server'),
        verifiedServerInstanceIdProvider.overrideWith((ref) async => 'A'),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        offlinePageStoreProvider.overrideWithValue(store),
        offlineDownloadCoordinatorProvider.overrideWithValue(coordinator),
        offlineDownloadManagerProvider.overrideWithValue(null),
        mangaBookRepositoryProvider.overrideWithValue(
          MangaBookRepository(_inertClient()),
        ),
        notificationsControllerProvider.overrideWith(
          (ref) => StartupNotifications(ref, () async {}),
        ),
        // What the real settled provider reports while any refresh is in
        // flight — and active downloads keep one going almost constantly.
        // `_resume()` must judge on the access it just awaited, not this.
        settledAccountAccessProvider.overrideWithValue(
          AccountAccess(capability: AccountCapability.unknown),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    await coordinator.pumped.future.timeout(const Duration(seconds: 2));
  });

  test(
    'offline turning on during the launch pass it is read by runs no second pass',
    () async {
      // At launch offline turns on as soon as the server identity loads,
      // while the pass that awaited it is still running and about to read it.
      var verifications = 0;
      late ProviderContainer container;
      container = await setup(
        verify: () async {
          verifications++;
          return 'catalog-a';
        },
        notify: () async {
          container.read(_offlineProvider.notifier).set(true);
          container.read(offlineActiveProvider);
          await pumpEventQueue();
          // Off again before the pass reads it, so the test stays out of the
          // offline launch path; what's checked is only whether it reruns.
          container.read(_offlineProvider.notifier).set(false);
          container.read(offlineActiveProvider);
        },
      );
      final startup = AccountSessionStartup(container);
      addTearDown(startup.dispose);
      await startup.start();
      await pumpEventQueue();
      expect(verifications, 1);
    },
  );

  test('offline turning on between passes still starts one', () async {
    var verifications = 0;
    final container = await setup(
      verify: () async {
        verifications++;
        return 'catalog-a';
      },
      notify: () async {},
    );
    final startup = AccountSessionStartup(container);
    addTearDown(startup.dispose);
    await startup.start();
    expect(verifications, 1);
    container.read(_offlineProvider.notifier).set(true);
    await pumpEventQueue();
    expect(verifications, 2);
  });
}
