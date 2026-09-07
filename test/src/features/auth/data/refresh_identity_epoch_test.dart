import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_state.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _DelayedRefresh extends Link {
  final requested = Completer<Request>();
  final response = Completer<Response>();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requested.complete(request);
    yield await response.future;
  }
}

class _ControlledSecureStorage extends FlutterSecureStorage {
  String? blockedOperation;
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> _wait(String operation, String key) async {
    if (blockedOperation != operation || key != 'auth.ui.accessToken') return;
    blockedOperation = null;
    entered.complete();
    await release.future;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _wait('write', key);
    await super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _wait('delete', key);
    await super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

Response _success(String accessToken) => Response(
  data: {
    '__typename': 'Mutation',
    'refreshToken': {
      '__typename': 'RefreshTokenPayload',
      'accessToken': accessToken,
    },
  },
  response: const {},
);

Response _rejection() => Response(
  errors: [GraphQLError(message: 'Refresh token rejected')],
  response: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late AuthCredentialsStore store;
  late _DelayedRefresh link;
  late GraphQLClient client;
  late _ControlledSecureStorage storage;

  setUp(() async {
    debugResetAuthCoordinatorSingleFlight();
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'account-a-access',
      'auth.ui.refreshToken': 'account-a-refresh',
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    final prefs = await SharedPreferences.getInstance();
    storage = _ControlledSecureStorage();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    await container.read(authCredentialsStoreProvider.future);
    store = container.read(authCredentialsStoreProvider.notifier);
    link = _DelayedRefresh();
    client = GraphQLClient(link: link, cache: GraphQLCache());
  });

  tearDown(() {
    container.dispose();
    debugResetAuthCoordinatorSingleFlight();
  });

  Future<void> expectAccountB() async {
    final credentials = await container.read(
      authCredentialsStoreProvider.future,
    );
    expect(credentials.uiAccessToken, 'account-b-access');
    expect(credentials.uiRefreshToken, 'account-b-refresh');
    final secure = container.read(secureStorageProvider);
    expect(await secure.read(key: 'auth.ui.accessToken'), 'account-b-access');
    expect(await secure.read(key: 'auth.ui.refreshToken'), 'account-b-refresh');
    expect(container.read(needsReauthProvider), isFalse);
  }

  Future<void> saveAccountB() => store.saveUiLoginTokens(
    accessToken: 'account-b-access',
    refreshToken: 'account-b-refresh',
    forEpoch: store.serverEpoch,
  );

  test(
    'refresh stays blocked throughout the transition action and resumes afterwards',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final transition = store.withIdentityChange(() async {
        entered.complete();
        await release.future;
        await saveAccountB();
      });
      await entered.future;
      expect(store.identityChanging, isTrue);
      final blocked = await container
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(gqlClient: client);
      expect(blocked, isA<RefreshTransientFailure>());
      expect(link.requested.isCompleted, isFalse);
      release.complete();
      await transition;
      expect(store.identityChanging, isFalse);
      await expectAccountB();

      final refresh = container
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(gqlClient: client);
      final request = await link.requested.future;
      expect(request.variables['input'], {'refreshToken': 'account-b-refresh'});
      link.response.complete(_success('account-b-refreshed'));
      expect(await refresh, isA<RefreshSuccess>());
      final credentials = await container.read(
        authCredentialsStoreProvider.future,
      );
      expect(credentials.uiAccessToken, 'account-b-refreshed');
      expect(
        await storage.read(key: 'auth.ui.accessToken'),
        'account-b-refreshed',
      );
      expect(credentials.uiRefreshToken, 'account-b-refresh');
    },
  );

  test(
    'queued identity changes serialize and nested changes do not reacquire admission',
    () async {
      final firstEntered = Completer<void>();
      final firstRelease = Completer<void>();
      final secondEntered = Completer<void>();
      final secondRelease = Completer<void>();
      var nestedFinished = false;
      var secondStarted = false;
      final first = store.withIdentityChange(() async {
        firstEntered.complete();
        await firstRelease.future;
        await store.withIdentityChange(() async {
          await store.saveUiLoginTokens(
            accessToken: 'intermediate-access',
            refreshToken: 'intermediate-refresh',
            forEpoch: store.serverEpoch,
          );
        });
        nestedFinished = true;
      });
      await firstEntered.future;
      final second = store.withIdentityChange(() async {
        secondStarted = true;
        expect(nestedFinished, isTrue);
        secondEntered.complete();
        await secondRelease.future;
        await saveAccountB();
      });
      await pumpEventQueue();
      expect(secondStarted, isFalse);
      firstRelease.complete();
      await first;
      await secondEntered.future;
      expect(store.identityChanging, isTrue);
      final blocked = await container
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(gqlClient: client);
      expect(blocked, isA<RefreshTransientFailure>());
      expect(link.requested.isCompleted, isFalse);
      secondRelease.complete();
      await second;
      expect(store.identityChanging, isFalse);
      await expectAccountB();
    },
  );

  test(
    'a queued route handover preserves the login epoch captured by the active transition',
    () async {
      final loginStarted = Completer<void>();
      final loginResponse = Completer<void>();
      late int loginEpoch;
      final login = store.withIdentityChange(() async {
        loginEpoch = store.serverEpoch;
        loginStarted.complete();
        await loginResponse.future;
        expect(store.serverEpoch, loginEpoch);
        await store.saveUiLoginTokens(
          accessToken: 'account-b-access',
          refreshToken: 'account-b-refresh',
          forEpoch: loginEpoch,
        );
      });
      await loginStarted.future;
      var handedOver = false;
      final handover = store.withIdentityChange(() async {
        await expectAccountB();
        handedOver = true;
      });
      await pumpEventQueue();
      expect(store.serverEpoch, loginEpoch);
      expect(handedOver, isFalse);
      expect(store.identityChanging, isTrue);
      loginResponse.complete();
      await Future.wait([login, handover]);
      expect(handedOver, isTrue);
      expect(store.identityChanging, isFalse);
      await expectAccountB();
    },
  );

  for (final rejected in [false, true]) {
    test(
      'an earlier ${rejected ? 'rejection' : 'success'} arriving during a transition leaves the new login intact',
      () async {
        final refresh = container
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(gqlClient: client);
        await link.requested.future;
        final entered = Completer<void>();
        final release = Completer<void>();
        final transition = store.withIdentityChange(() async {
          await saveAccountB();
          entered.complete();
          await release.future;
        });
        await entered.future;
        link.response.complete(
          rejected ? _rejection() : _success('account-a-refreshed'),
        );
        expect(await refresh, isA<RefreshTransientFailure>());
        await expectAccountB();
        expect(store.identityChanging, isTrue);
        release.complete();
        await transition;
        expect(store.identityChanging, isFalse);
        await expectAccountB();
      },
    );
  }

  for (final clear in [false, true]) {
    test(
      'an in-flight secure ${clear ? 'clear' : 'write'} drains before transition login writes',
      () async {
        storage.blockedOperation = clear ? 'delete' : 'write';
        final mutation = clear
            ? store.clearUiLoginTokens(forEpoch: store.serverEpoch)
            : store.updateUiLoginAccessToken(
                'account-a-refreshed',
                forEpoch: store.serverEpoch,
              );
        await storage.entered.future;
        var actionStarted = false;
        final transition = store.withIdentityChange(() async {
          actionStarted = true;
          await saveAccountB();
        });
        expect(store.identityChanging, isTrue);
        final blocked = await container
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(gqlClient: client);
        expect(blocked, isA<RefreshTransientFailure>());
        expect(link.requested.isCompleted, isFalse);
        expect(actionStarted, isFalse);
        storage.release.complete();
        await mutation;
        await transition;
        expect(actionStarted, isTrue);
        expect(store.identityChanging, isFalse);
        await expectAccountB();
      },
    );

    test(
      'refresh finishing a secure ${clear ? 'clear' : 'write'} during transition returns transient',
      () async {
        storage.blockedOperation = clear ? 'delete' : 'write';
        final refresh = container
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(gqlClient: client);
        await link.requested.future;
        link.response.complete(
          clear ? _rejection() : _success('account-a-refreshed'),
        );
        await storage.entered.future;
        var actionStarted = false;
        final transition = store.withIdentityChange(() async {
          actionStarted = true;
          await saveAccountB();
        });
        expect(store.identityChanging, isTrue);
        await pumpEventQueue();
        expect(actionStarted, isFalse);
        storage.release.complete();
        expect(await refresh, isA<RefreshTransientFailure>());
        await transition;
        expect(actionStarted, isTrue);
        await expectAccountB();
      },
    );
  }

  for (final rejected in [false, true]) {
    test(
      'a delayed ${rejected ? 'rejected' : 'successful'} refresh cannot change a newer login',
      () async {
        final refresh = container
            .read(authCoordinatorProvider.notifier)
            .refreshUiAccessToken(gqlClient: client);
        final request = await link.requested.future;
        expect(request.variables['input'], {
          'refreshToken': 'account-a-refresh',
        });
        final previousEpoch = store.serverEpoch;
        store.invalidatePendingWrites();
        expect(store.serverEpoch, previousEpoch + 1);
        await store.saveUiLoginTokens(
          accessToken: 'account-b-access',
          refreshToken: 'account-b-refresh',
          forEpoch: store.serverEpoch,
        );
        link.response.complete(
          rejected ? _rejection() : _success('account-a-refreshed'),
        );

        expect(await refresh, isA<RefreshTransientFailure>());
        await expectAccountB();
      },
    );
  }

  test('a refresh for the current epoch still succeeds', () async {
    final refresh = container
        .read(authCoordinatorProvider.notifier)
        .refreshUiAccessToken(gqlClient: client);
    await link.requested.future;
    link.response.complete(_success('account-a-refreshed'));

    expect(await refresh, isA<RefreshSuccess>());
    final credentials = await container.read(
      authCredentialsStoreProvider.future,
    );
    expect(credentials.uiAccessToken, 'account-a-refreshed');
    expect(credentials.uiRefreshToken, 'account-a-refresh');
  });

  test(
    'a rejected refresh for the current epoch still clears the expired login',
    () async {
      final refresh = container
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(gqlClient: client);
      await link.requested.future;
      link.response.complete(_rejection());

      expect(await refresh, isA<RefreshAuthFailure>());
      final credentials = await container.read(
        authCredentialsStoreProvider.future,
      );
      expect(credentials.uiAccessToken, isNull);
      expect(credentials.uiRefreshToken, isNull);
      expect(container.read(needsReauthProvider), isTrue);
    },
  );

  for (final offset in [-1, 1]) {
    test(
      'credential writes reject ${offset < 0 ? 'past' : 'future'} epochs',
      () async {
        store.invalidatePendingWrites();
        await store.saveUiLoginTokens(
          accessToken: 'account-b-access',
          refreshToken: 'account-b-refresh',
          forEpoch: store.serverEpoch,
        );
        final invalidEpoch = store.serverEpoch + offset;
        await store.saveUiLoginTokens(
          accessToken: 'wrong-access',
          refreshToken: 'wrong-refresh',
          forEpoch: invalidEpoch,
        );
        await store.updateUiLoginAccessToken(
          'wrong-access',
          forEpoch: invalidEpoch,
        );

        await expectAccountB();
      },
    );
  }
}
