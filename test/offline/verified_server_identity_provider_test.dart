import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _IdentityRepository extends OfflineServerIdentityRepository {
  _IdentityRepository(super.client);

  Future<String> Function() resolveIdentity = () async => 'catalog-A';

  @override
  Future<String> resolve() => resolveIdentity();
}

class _Fixture {
  _Fixture(this.preferences) {
    repository = _IdentityRepository(
      GraphQLClient(
        link: Link.function((request, [forward]) async* {
          if (offline) throw const SocketException('offline');
          yield Response(
            response: const {},
            data: {
              '__typename': 'Query',
              'user': {
                '__typename': 'UserType',
                'id': userId,
                'username': 'reader-$userId',
                'permissions': <String>[],
                'roles': ['USER'],
              },
            },
          );
        }),
        cache: GraphQLCache(),
        defaultPolicies: DefaultPolicies(
          query: Policies(fetch: FetchPolicy.noCache),
        ),
      ),
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        currentServerAddressProvider.overrideWithValue(address),
        offlineServerIdentityRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  static const address = 'https://reader.test';
  final SharedPreferences preferences;
  late final _IdentityRepository repository;
  late final ProviderContainer container;
  int userId = 1;
  bool offline = false;

  static AccountBinding binding(String account, int userId) => AccountBinding(
    address: address,
    userId: userId,
    username: 'reader-$userId',
    catalogId: 'catalog-$account',
  );

  static Future<_Fixture> create() async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A-access',
      'auth.ui.refreshToken': 'A-refresh',
      'auth.ui.accountBinding': binding(
        'A',
        1,
      ).encode(accessToken: 'A-access', refreshToken: 'A-refresh'),
    });
    SharedPreferences.setMockInitialValues({
      CatchupStateStore.identityAuthorizedKey: false,
    });
    final fixture = _Fixture(await SharedPreferences.getInstance());
    await fixture.container.read(authCredentialsStoreProvider.future);
    return fixture;
  }

  Future<void> switchToB() async {
    userId = 2;
    await container
        .read(authCredentialsStoreProvider.notifier)
        .saveUiLoginTokens(
          accessToken: 'B-access',
          refreshToken: 'B-refresh',
          binding: binding('B', 2),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;

  setUp(() async => fixture = await _Fixture.create());
  tearDown(() => fixture.container.dispose());

  test('matching account and catalogue authorize background work', () async {
    expect(
      await fixture.container.read(verifiedServerInstanceIdProvider.future),
      'catalog-A',
    );
    expect(CatchupStateStore(fixture.preferences).identityAuthorized, isTrue);
    expect(
      fixture.preferences.getString(DBKeys.offlineLastServerId.name),
      'catalog-A',
    );
    expect(
      fixture.preferences.getString(DBKeys.offlineLastServerAddress.name),
      _Fixture.address,
    );
  });

  for (final mismatch in ['account', 'catalogue']) {
    test('a different $mismatch revokes background authorization', () async {
      await CatchupStateStore(fixture.preferences).setIdentityAuthorized(true);
      await fixture.preferences.setString(
        DBKeys.offlineLastServerId.name,
        'previous-verified',
      );
      if (mismatch == 'account') {
        fixture.userId = 2;
      } else {
        fixture.repository.resolveIdentity = () async => 'catalog-B';
      }
      await expectLater(
        fixture.container.read(verifiedServerInstanceIdProvider.future),
        throwsStateError,
      );
      expect(
        CatchupStateStore(fixture.preferences).identityAuthorized,
        isFalse,
      );
      expect(
        fixture.preferences.getString(DBKeys.offlineLastServerId.name),
        'previous-verified',
      );
    });
  }

  test('late A verification cannot overwrite verified B identity', () async {
    final started = Completer<void>();
    final delayedA = Completer<String>();
    fixture.repository.resolveIdentity = () {
      if (fixture.userId == 1) {
        started.complete();
        return delayedA.future;
      }
      return Future.value('catalog-B');
    };
    final oldResult = fixture.container
        .read(verifiedServerInstanceIdProvider.future)
        .then<Object>((value) => value, onError: (Object error) => error);
    await started.future;
    await fixture.switchToB();
    expect(
      await fixture.container.read(verifiedServerInstanceIdProvider.future),
      'catalog-B',
    );
    delayedA.complete('catalog-A');
    await oldResult;
    await fixture.container.pump();
    expect(
      fixture.preferences.getString(DBKeys.offlineLastServerId.name),
      'catalog-B',
    );
    expect(CatchupStateStore(fixture.preferences).identityAuthorized, isTrue);
  });

  test('offline LAN alias keeps the bound local catalogue available', () async {
    fixture.offline = true;
    fixture.container.updateOverrides([
      sharedPreferencesProvider.overrideWithValue(fixture.preferences),
      authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
      currentServerAddressProvider.overrideWithValue('http://192.0.2.10:4567'),
      offlineServerIdentityRepositoryProvider.overrideWithValue(
        fixture.repository,
      ),
    ]);
    expect(
      await fixture.container.read(serverInstanceIdProvider.future),
      'catalog-A',
    );
    await expectLater(
      fixture.container.read(verifiedServerInstanceIdProvider.future),
      throwsA(anything),
    );
    expect(CatchupStateStore(fixture.preferences).identityAuthorized, isFalse);
    expect(
      await fixture.container.read(serverInstanceIdProvider.future),
      'catalog-A',
    );
  });
}
