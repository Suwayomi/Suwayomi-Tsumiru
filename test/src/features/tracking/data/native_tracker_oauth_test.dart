import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/credential_snapshot.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_io.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/tracking/data/native_tracker_oauth.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import 'oauth_test_pending_store.dart';
import 'oauth_test_storage.dart';

class _Repository extends TrackerRepository {
  _Repository()
    : super(
        GraphQLClient(
          cache: GraphQLCache(),
          link: Link.function((_, [forward]) => const Stream.empty()),
        ),
      );
  final calls = <int>[];
  @override
  Future<void> loginOAuth({
    required int trackerId,
    required String callbackUrl,
  }) async => calls.add(trackerId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late OAuthTestStorage storage;
  late _Repository repository;
  late OAuthTestPendingStore pending;
  late String pendingPath;
  late DateTime clock;
  late String origin;
  late String opened;
  late int launches;

  setUp(() async {
    debugResetKeychainRefusal();
    SharedPreferences.setMockInitialValues({
      'serverExternalUrl': 'https://server.test',
      'authUsername': 'Reader',
    });
    preferences = await SharedPreferences.getInstance();
    storage = OAuthTestStorage();
    final directory = await Directory.systemTemp.createTemp(
      'oauth-pending-test-',
    );
    pendingPath = '${directory.path}/pending.sqlite';
    pending = OAuthTestPendingStore(
      SqlitePendingTrackerOAuthStore(path: pendingPath),
    );
    repository = _Repository();
    clock = DateTime.utc(2026, 10, 21);
    origin = 'origin-A';
    opened = '';
    launches = 0;
  });
  Future<ProviderContainer> container() async {
    final value = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        secureStorageProvider.overrideWithValue(storage),
        pendingTrackerOAuthStoreProvider.overrideWithValue(pending),
        trackerRepositoryProvider.overrideWithValue(repository),
        authTypeKeyProvider.overrideWithValue(AuthType.basic),
      ],
    );
    addTearDown(value.dispose);
    await value.read(authCredentialsStoreProvider.future);
    return value;
  }

  NativeTrackerOAuth guard(
    ProviderContainer container, {
    bool actualOrigin = false,
  }) {
    final actual = container.read(nativeTrackerOAuthProvider);
    return NativeTrackerOAuth(
      pending: actual.pending,
      captureSession: actual.captureSession,
      readOrigin: actualOrigin ? actual.readOrigin : (_) async => origin,
      loginOAuth: actual.loginOAuth,
      onSuccess: actual.onSuccess,
      now: () => clock,
    );
  }

  Future<TrackerOAuthBeginOutcome> begin(NativeTrackerOAuth handler) =>
      handler.begin(
        authUrl: 'https://tracker.test/authorize?client_id=public',
        trackerId: 1,
        trackerName: 'AniList',
        launch: (url) async {
          opened = url;
          launches++;
        },
      );
  Map<String, dynamic> state() =>
      jsonDecode(Uri.parse(opened).queryParameters['state']!)
          as Map<String, dynamic>;
  Uri callback({Map<String, dynamic> changes = const {}}) => Uri(
    scheme: 'tsumiru',
    host: 'tracker-oauth',
    queryParameters: {
      'access_token': 'example-token',
      'state': jsonEncode({...state(), ...changes}),
    },
  );
  Future<void> coldStart() async {
    final saved = {
      for (final key in preferences.getKeys()) key: preferences.get(key)!,
    };
    SharedPreferences.setMockInitialValues(saved);
    preferences = await SharedPreferences.getInstance();
    debugResetKeychainRefusal();
  }

  test(
    'the actual native callback boundary refuses an unsolicited tracker login',
    () async {
      final handler = guard(await container());
      final uri = Uri(
        scheme: 'tsumiru',
        host: 'tracker-oauth',
        queryParameters: {
          'access_token': 'attacker-token',
          'state': jsonEncode({
            'trackerId': 1,
            'redirectUrl': nativeTrackerOAuthRedirect,
          }),
        },
      );
      expect(await handler.handleCallback(uri), TrackerOAuthOutcome.rejected);
      expect(repository.calls, isEmpty);
    },
  );
  test(
    'matching callback uses actual origin wiring, preserves bridge fields and is one use',
    () async {
      final handler = guard(await container(), actualOrigin: true);
      expect(await begin(handler), TrackerOAuthBeginOutcome.started);
      expect(state(), containsPair('redirectUrl', nativeTrackerOAuthRedirect));
      expect(state(), containsPair('trackerId', 1));
      expect(state(), containsPair('trackerName', 'AniList'));
      expect(state()['nonce'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(
        await handler.handleCallback(callback()),
        TrackerOAuthOutcome.succeeded,
      );
      expect(
        await handler.handleCallback(callback()),
        TrackerOAuthOutcome.rejected,
      );
      expect(repository.calls, [1]);
    },
  );
  for (final change in [
    {'nonce': 'wrong'},
    {'trackerId': 2},
    {'redirectUrl': 'tsumiru://other'},
  ]) {
    test('callback rejects mismatched ${change.keys.single}', () async {
      final handler = guard(await container());
      await begin(handler);
      await handler.handleCallback(callback(changes: change));
      expect(repository.calls, isEmpty);
    });
  }
  test(
    'callback rejects duplicate state parameters and altered native base',
    () async {
      final handler = guard(await container());
      await begin(handler);
      final duplicate = Uri(
        scheme: 'tsumiru',
        host: 'tracker-oauth',
        queryParameters: {
          'state': [jsonEncode(state()), jsonEncode(state())],
        },
      );
      await handler.handleCallback(duplicate);
      for (final uri in [
        callback().replace(path: '/extra'),
        callback().replace(userInfo: 'other'),
        callback().replace(port: 42),
        callback().replace(fragment: 'other'),
      ]) {
        await handler.handleCallback(uri);
      }
      expect(repository.calls, isEmpty);
    },
  );
  for (final delta in [
    const Duration(minutes: 11),
    const Duration(minutes: -1),
  ]) {
    test('callback rejects expired or future-issued request: $delta', () async {
      final handler = guard(await container());
      await begin(handler);
      clock = clock.add(delta);
      await handler.handleCallback(callback());
      expect(repository.calls, isEmpty);
    });
  }
  test(
    'callback rejects a different current server or account origin',
    () async {
      final handler = guard(await container());
      await begin(handler);
      origin = 'origin-B';
      await handler.handleCallback(callback());
      expect(repository.calls, isEmpty);
    },
  );
  test(
    'concurrent duplicate deliveries across containers claim one durable request',
    () async {
      final first = guard(await container());
      final second = guard(await container());
      expect(identical(first.pending, second.pending), isTrue);
      await begin(first);
      await Future.wait([
        first.handleCallback(callback()),
        second.handleCallback(callback()),
      ]);
      expect(repository.calls, [1]);
    },
  );
  test('persisted request survives a process restart', () async {
    final first = guard(await container());
    await begin(first);
    final uri = callback();
    await coldStart();
    final second = guard(await container());
    expect(await second.pending.read(), isNotNull);
    await second.handleCallback(uri);
    expect(repository.calls, [1]);
  });
  test('a new flow replaces the previous request', () async {
    final handler = guard(await container());
    await begin(handler);
    final old = callback();
    await begin(handler);
    await handler.handleCallback(old);
    expect(repository.calls, isEmpty);
    await handler.handleCallback(callback());
    expect(repository.calls, [1]);
  });
  for (final failCancel in [false, true]) {
    test(
      'A to B to A cancels durably; a refused cancellation blocks the transition=$failCancel',
      () async {
        final c = await container();
        final handler = guard(c);
        await begin(handler);
        final uri = callback();
        final auth = c.read(authCredentialsStoreProvider.notifier);
        if (failCancel) {
          pending.failCancel = true;
          await expectLater(
            auth.withIdentityChange(() async {
              origin = 'origin-B';
            }),
            throwsStateError,
          );
          expect(origin, 'origin-A');
          expect(await pending.read(), isNotNull);
          pending.failCancel = false;
        }
        await auth.withIdentityChange(() async {
          origin = 'origin-B';
        });
        await auth.withIdentityChange(() async {
          origin = 'origin-A';
        });
        expect(await pending.read(), isNull);
        await coldStart();
        await guard(await container()).handleCallback(uri);
        expect(repository.calls, isEmpty);
      },
    );
  }
  test(
    'JWT refresh and session-preserving LAN handover retain pending request',
    () async {
      final c = await container();
      final auth = c.read(authCredentialsStoreProvider.notifier);
      await auth.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
      final handler = guard(c);
      await begin(handler);
      final uri = callback();
      expect(
        await auth.refreshUiLoginTokens(
          accessToken: 'A2',
          refreshToken: 'R2',
          originalRefreshToken: 'R',
          forEpoch: auth.serverEpoch,
        ),
        isTrue,
      );
      await auth.withIdentityChange(() async {}, preserveSession: true);
      await handler.handleCallback(uri);
      expect(repository.calls, [1]);
    },
  );
  test(
    'ordinary identity change with no pending request adds no credential writes',
    () async {
      final c = await container();
      await pumpEventQueue();
      final writes = storage.writes;
      final deletes = storage.deletes;
      expect(await File(pendingPath).exists(), isFalse);
      await c
          .read(authCredentialsStoreProvider.notifier)
          .withIdentityChange(() async {});
      expect(storage.writes, writes);
      expect(storage.deletes, deletes);
      expect(await File(pendingPath).exists(), isFalse);
    },
  );
  test('failed begin persistence never opens the browser', () async {
    final handler = guard(await container());
    pending.failReplace = true;
    expect(await begin(handler), TrackerOAuthBeginOutcome.saveFailed);
    expect(launches, 0);
    expect(await pending.read(), isNull);
  });
  test('failed consumption persistence never dispatches a mutation', () async {
    final handler = guard(await container());
    await begin(handler);
    pending.failClaim = true;
    await handler.handleCallback(callback());
    expect(repository.calls, isEmpty);
    expect(await pending.read(), isNotNull);
    pending.failClaim = false;
    await handler.handleCallback(callback());
    expect(repository.calls, [1]);
  });
  test('a superseded begin cannot launch or clear the newer request', () async {
    final handler = guard(await container());
    final entered = Completer<void>();
    final release = Completer<void>();
    var blocked = false;
    pending.afterReplace = () async {
      if (!blocked) {
        blocked = true;
        entered.complete();
        await release.future;
      }
    };
    final first = begin(handler);
    await entered.future;
    final oldPending = await pending.read();
    final second = begin(handler);
    await pumpEventQueue();
    expect(await pending.read(), isNot(oldPending));
    release.complete();
    expect(await first, TrackerOAuthBeginOutcome.superseded);
    expect(await second, TrackerOAuthBeginOutcome.started);
    expect(launches, 1);
    expect(
      await handler.handleCallback(callback()),
      TrackerOAuthOutcome.succeeded,
    );
  });

  test('identity change while begin persists prevents launch', () async {
    final c = await container();
    final handler = guard(c);
    final entered = Completer<void>();
    final release = Completer<void>();
    pending.afterReplace = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final opening = begin(handler);
    await entered.future;
    final changing = c
        .read(authCredentialsStoreProvider.notifier)
        .withIdentityChange(() async {});
    release.complete();
    await Future.wait([opening, changing]);
    expect(launches, 0);
    expect(await pending.read(), isNull);
  });
  test(
    'identity change while consumption persists prevents mutation',
    () async {
      final c = await container();
      final handler = guard(c);
      await begin(handler);
      final uri = callback();
      final entered = Completer<void>();
      final release = Completer<void>();
      pending.afterClaim = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final consuming = handler.handleCallback(uri);
      await entered.future;
      final changing = c
          .read(authCredentialsStoreProvider.notifier)
          .withIdentityChange(() async {});
      release.complete();
      await Future.wait([consuming, changing]);
      expect(repository.calls, isEmpty);
    },
  );
  test(
    'failed cancellation preserves unchanged activated auth without reviving old closures',
    () async {
      final c = await container();
      final auth = c.read(authCredentialsStoreProvider.notifier);
      await auth.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
      auth.activateSession();
      final handler = guard(c);
      await begin(handler);
      final previous = auth.captureSession();
      pending.failCancel = true;
      var actionRan = false;
      await expectLater(
        auth.withIdentityChange(() async {
          actionRan = true;
        }),
        throwsStateError,
      );
      expect(actionRan, isFalse);
      expect(c.read(authCredentialsStoreProvider).value?.uiAccessToken, 'A');
      expect(auth.sessionAdmitted, isTrue);
      expect(previous(), isFalse);
      expect(auth.captureSession()(), isTrue);
      expect(await pending.read(), isNotNull);
      pending.failCancel = false;
      await handler.handleCallback(callback());
      expect(repository.calls, [1]);
    },
  );
  for (final activated in [false, true]) {
    test(
      'concurrent cancellation refusals preserve admission with activated=$activated',
      () async {
        final c = await container();
        final auth = c.read(authCredentialsStoreProvider.notifier);
        if (activated) auth.activateSession();
        final previous = auth.captureSession();
        final entered = Completer<void>();
        final release = Completer<void>();
        pending.failCancel = true;
        pending.beforeCancel = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        var actions = 0;
        final first = auth.withIdentityChange(() async {
          actions++;
        });
        await entered.future;
        final second = auth.withIdentityChange(() async {
          actions++;
        });
        var failures = 0;
        final completed = Future.wait([
          first.then<void>(
            (_) {},
            onError: (Object _) {
              failures++;
            },
          ),
          second.then<void>(
            (_) {},
            onError: (Object _) {
              failures++;
            },
          ),
        ]);
        release.complete();
        await completed;
        expect(failures, 2);
        expect(actions, 0);
        expect(pending.cancellations, activated ? 1 : 2);
        expect(auth.sessionAdmitted, isTrue);
        expect(previous(), isFalse);
      },
    );
  }
  test('failed cancellation never readmits a retired session', () async {
    final c = await container();
    final auth = c.read(authCredentialsStoreProvider.notifier);
    auth.activateSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    pending.failCancel = true;
    pending.beforeCancel = () async {
      entered.complete();
      await release.future;
    };
    final changing = auth.withIdentityChange(() async {});
    await entered.future;
    final retired = auth.retire();
    release.complete();
    await expectLater(changing, throwsStateError);
    await retired;
    expect(auth.sessionAdmitted, isFalse);
  });
  test(
    'failure after identity action starts does not restore old session admission',
    () async {
      final c = await container();
      final auth = c.read(authCredentialsStoreProvider.notifier);
      auth.activateSession();
      await expectLater(
        auth.withIdentityChange(() async {
          throw StateError('action failed');
        }),
        throwsStateError,
      );
      expect(auth.sessionAdmitted, isFalse);
    },
  );
  test('unavailable pending reads neither launch nor mutate', () async {
    final handler = guard(await container());
    pending.failRead = true;
    expect(await begin(handler), TrackerOAuthBeginOutcome.failed);
    expect(launches, 0);
    pending.failRead = false;
    await begin(handler);
    pending.failRead = true;
    await handler.handleCallback(callback());
    expect(repository.calls, isEmpty);
  });

  test(
    'ordinary unsaved auth still works after credential persistence refusal',
    () async {
      final c = await container();
      storage.failWrites.add(kUiAccessTokenSecureKey);
      final auth = c.read(authCredentialsStoreProvider.notifier);
      await auth.saveUiLoginTokens(accessToken: 'unsaved-A', refreshToken: 'R');
      expect(
        c.read(authCredentialsStoreProvider).value?.uiAccessToken,
        'unsaved-A',
      );
      expect(credentialsInvalidated(preferences), isTrue);
    },
  );
}
