// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/basic_auth_migration.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/auth/presentation/sign_in_action.dart';
import 'package:tsumiru/src/features/offline/data/background/record_seal.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

class _DeniedStorage implements FlutterSecureStorage {
  _DeniedStorage({this.failWrites = false});
  final bool failWrites;
  int reads = 0;
  int writeAttempts = 0;
  final List<String> writes = [];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    throw PlatformException(code: '-128', message: 'User canceled');
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
    writeAttempts++;
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    writes.add(key);
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
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _InMemoryStorage implements FlutterSecureStorage {
  _InMemoryStorage(this._store);
  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A readable, writable store whose writes or deletes can start failing, to
/// model the keychain refusing partway through a run.
class _FlakyStorage implements FlutterSecureStorage {
  _FlakyStorage(this.store, {this.failDeletes = false});
  final Map<String, String> store;
  bool failWrites = false;
  bool failDeletes;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

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
    if (failWrites) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
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
    if (failDeletes) {
      throw PlatformException(code: '-25293', message: 'User denied');
    }
    store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

late SharedPreferences _prefs;

ProviderContainer _container(FlutterSecureStorage storage) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      sharedPreferencesProvider.overrideWithValue(_prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _testToken() {
  final payload = jsonEncode({
    'exp':
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
        1000,
  });
  return 'e30.${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}.test-signature';
}

/// Answers the real sign-in path: the `Login` mutation, then the account
/// resolution the store commits behind it.
class _UiLoginChain extends Link {
  final operations = <String>[];
  final token = _testToken();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final operation = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(operation);
    final user = {
      '__typename': 'UserType',
      'id': 2,
      'username': 'Reader',
      'roles': ['USER'],
      'permissions': <String>[],
    };
    final payload = switch (operation) {
      'Login' => {
        'login': {
          '__typename': 'LoginPayload',
          'accessToken': token,
          'refreshToken': 'test-refresh',
        },
      },
      'AccountCapability' || 'CurrentAccount' => {'user': user},
      'OfflineServerIdentity' => {
        'metas': {
          '__typename': 'MetaTypeConnection',
          'nodes': [
            {
              '__typename': 'GlobalMetaType',
              'key': 'tsumiru_server_instance_id',
              'value': 'keychain-test-catalog',
            },
          ],
        },
      },
      _ => throw StateError('Unexpected test operation: $operation'),
    };
    yield Response(
      response: {},
      data: {
        '__typename': operation == 'Login' ? 'Mutation' : 'Query',
        ...payload,
      },
    );
  }
}

Future<SharedPreferences> _uiLoginPreferences() async {
  SharedPreferences.setMockInitialValues({
    DBKeys.authType.name: AuthType.uiLogin.index,
  });
  return SharedPreferences.getInstance();
}

ProviderContainer _sessionContainer(
  FlutterSecureStorage storage,
  SharedPreferences prefs,
  _UiLoginChain chain,
) => ProviderContainer(
  overrides: [
    secureStorageProvider.overrideWithValue(storage),
    sharedPreferencesProvider.overrideWithValue(prefs),
    unauthenticatedGraphQlClientProvider.overrideWithValue(
      GraphQLClient(link: chain, cache: GraphQLCache()),
    ),
  ],
);

class _RecordingToast extends Toast {
  // The super parameter is private to the Toast library.
  // ignore: use_super_parameters
  _RecordingToast(BuildContext context) : super(context);
  final messages = <String>[];

  @override
  void show(
    String msg, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) => messages.add(msg);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    debugResetKeychainRefusal();
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  test(
    'a refused keychain read leaves the credentials absent instead of stalling startup',
    () async {
      final container = _container(_DeniedStorage());

      final auth = await container
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      final basic = await container
          .read(credentialsProvider.future)
          .timeout(const Duration(seconds: 5));
      final headers = await container
          .read(customHttpHeadersProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(auth.uiAccessToken, isNull);
      expect(auth.uiRefreshToken, isNull);
      expect(auth.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(headers, isEmpty);
    },
  );

  test('startup asks the keychain once when it refuses a read', () async {
    final storage = _DeniedStorage();
    final container = _container(storage);

    final auth = await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));
    final basic = await container
        .read(credentialsProvider.future)
        .timeout(const Duration(seconds: 5));
    final headers = await container
        .read(customHttpHeadersProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(storage.reads, 1);
    expect(auth.uiAccessToken, isNull);
    expect(basic, isNull);
    expect(headers, isEmpty);
  });

  test('a refused keychain never creates a new record key', () async {
    RecordSeal.debugKey = null;
    final storage = _DeniedStorage();
    await RecordSeal.load(
      storage,
      create: true,
    ).timeout(const Duration(seconds: 5));
    expect(RecordSeal.ready, isFalse);
    expect(storage.reads, 1);
    expect(storage.writes, isEmpty);
  });

  test('a refused keychain read is not retried', () async {
    final storage = _DeniedStorage();
    final container = _container(storage);

    await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));
    await container
        .read(credentialsProvider.future)
        .timeout(const Duration(seconds: 5));
    final readsAfterLoad = storage.reads;

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(storage.reads, readsAfterLoad);
  });

  test('a readable keychain still loads the stored credentials', () async {
    final container = _container(
      _InMemoryStorage({
        'auth.simple.cookie': 'JSESSIONID=abc123',
        kBasicCredentialsSecureKey: 'Basic abc',
      }),
    );

    final auth = await container.read(authCredentialsStoreProvider.future);
    final basic = await container.read(credentialsProvider.future);

    expect(auth.simpleLoginCookie, 'JSESSIONID=abc123');
    expect(basic, 'Basic abc');
  });

  test(
    'a fresh sign-in after a refused read reaches the authenticated request path',
    () async {
      final storage = _DeniedStorage();
      final prefs = await _uiLoginPreferences();
      final chain = _UiLoginChain();

      final first = _sessionContainer(storage, prefs, chain);
      addTearDown(first.dispose);
      final refused = await first
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      expect(refused.uiAccessToken, isNull);

      await first
          .read(authCoordinatorProvider.notifier)
          .loginUi(
            gqlClient: GraphQLClient(link: chain, cache: GraphQLCache()),
            username: 'reader',
            password: 'password',
          )
          .timeout(const Duration(seconds: 5));
      expect(storage.reads, 1);

      // The sign-in restarts the session container; that container must see
      // the new token without asking the keychain again.
      final restarted = _sessionContainer(storage, prefs, chain);
      addTearDown(restarted.dispose);
      final token = await restarted
          .read(authCoordinatorProvider.notifier)
          .usableUiAccessToken(
            gqlClient: () => throw StateError('unexpected refresh'),
            trigger: 'test',
          )
          .timeout(const Duration(seconds: 5));

      expect(token, chain.token);
      expect(storage.reads, 1);
    },
  );

  testWidgets('a refused write still signs in and shows one notice', (
    tester,
  ) async {
    final storage = _DeniedStorage(failWrites: true);
    final prefs = await _uiLoginPreferences();
    final chain = _UiLoginChain();
    late WidgetRef ref;
    late String notice;
    late _RecordingToast toast;

    // A throwaway tree, so the recording toast has a context to build from.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            toast = _RecordingToast(context);
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sharedPreferencesProvider.overrideWithValue(prefs),
          unauthenticatedGraphQlClientProvider.overrideWithValue(
            GraphQLClient(link: chain, cache: GraphQLCache()),
          ),
          toastProvider.overrideWithValue(toast),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, widgetRef, _) {
              ref = widgetRef;
              notice = context.l10n.authCredentialsNotSaved;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));

    await performSignIn(
      ref,
      authType: AuthType.uiLogin,
      serverBaseUrl: 'http://127.0.0.1',
      username: 'reader',
      password: 'password',
    ).timeout(const Duration(seconds: 5));

    expect(storage.writeAttempts, greaterThan(0));
    final token = await container
        .read(authCoordinatorProvider.notifier)
        .usableUiAccessToken(
          gqlClient: () => throw StateError('unexpected refresh'),
          trigger: 'test',
        )
        .timeout(const Duration(seconds: 5));
    expect(token, chain.token);
    expect(toast.messages, [notice]);

    // Tear the scope down so the proactive-refresh timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'a switch whose credential delete is refused cannot reuse the old sign-in after restart',
    () async {
      final backing = <String, String>{
        'auth.ui.accessToken': _testToken(),
        'auth.ui.refreshToken': 'old-refresh',
        kBasicCredentialsSecureKey: 'Basic old',
      };
      final first = _container(_FlakyStorage(backing, failDeletes: true));
      final beforeSwitch = await first.read(authCredentialsStoreProvider.future);
      expect(beforeSwitch.uiAccessToken, isNotNull);
      expect(backing, isNotEmpty);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isTrue);
      expect(backing, isNotEmpty);

      // Next launch: the keychain works again, but the old sign-in survived
      // the switch and belongs to the previous server.
      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final afterRestart = await restarted.read(
        authCredentialsStoreProvider.future,
      );
      final basic = await restarted.read(credentialsProvider.future);

      expect(afterRestart.uiAccessToken, isNull);
      expect(afterRestart.uiRefreshToken, isNull);
      expect(afterRestart.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(backing, isEmpty);
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isFalse);
    },
  );

  test(
    'a fully saved sign-in clears the marker instead of being discarded next launch',
    () async {
      // Phase 1: the marker is set by a switch whose deletes the keychain
      // refuses, leaving the old server's credentials in storage.
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-token',
        'auth.ui.refreshToken': 'old-refresh',
        kBasicCredentialsSecureKey: 'Basic old',
      };
      final storage = _FlakyStorage(backing, failDeletes: true);
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);
      await first
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isTrue);
      expect(backing, isNotEmpty);

      // The user grants access: the sign-in saves, and the credentials it did
      // not write are deleted, so the marker has nothing left to protect.
      storage.failDeletes = false;
      final token = _testToken();
      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(accessToken: token, refreshToken: 'new-refresh');

      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isFalse);
      expect(backing['auth.ui.accessToken'], token);
      expect(backing['auth.ui.refreshToken'], 'new-refresh');
      expect(backing[kBasicCredentialsSecureKey], isNull);

      // Next launch reads the fresh sign-in rather than deleting it as stale.
      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final afterRestart = await restarted.read(
        authCredentialsStoreProvider.future,
      );
      expect(afterRestart.uiAccessToken, token);
      expect(afterRestart.uiRefreshToken, 'new-refresh');
      expect(afterRestart.uiAuthorizationHeader, {
        'Authorization': 'Bearer $token',
      });
      expect(await restarted.read(credentialsProvider.future), isNull);
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isFalse);

      // Phase 2: the sign-in saves, but the stale-key deletes still fail, so
      // the marker stays and the next launch keeps treating storage as stale.
      debugResetKeychainRefusal();
      final stale = <String, String>{
        'auth.simple.cookie': 'JSESSIONID=old',
        kBasicCredentialsSecureKey: 'Basic old',
      };
      final refused = _FlakyStorage(stale, failDeletes: true);
      final second = _container(refused);
      await second.read(authCredentialsStoreProvider.future);
      await second
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isTrue);

      await second
          .read(authCredentialsStoreProvider.notifier)
          .saveSimpleLoginCookie('JSESSIONID=new');

      expect(stale['auth.simple.cookie'], 'JSESSIONID=new');
      expect(_prefs.getBool(DBKeys.authCredentialsInvalidated.name), isTrue);
    },
  );

  test('a header read before a refused write still loads afterwards', () async {
    final storage = _FlakyStorage({
      'custom.headers': '{"CF-Access-Client-Id":"abc"}',
    });
    final container = _container(storage);
    expect(
      await container.read(customHttpHeadersProvider.future),
      {'CF-Access-Client-Id': 'abc'},
    );

    storage.failWrites = true;
    expect(await writeSecure(storage, 'auth.simple.cookie', 'x'), isFalse);

    // The refused write flips the process-wide refusal; a provider rebuilt
    // after it must still see what was already read this run.
    container.invalidate(customHttpHeadersProvider);
    expect(await container.read(customHttpHeadersProvider.future), {
      'CF-Access-Client-Id': 'abc',
    });
  });

  test('a refused legacy password cleanup does not stop credential reads', () async {
    final token = _testToken();
    final storage = _FlakyStorage(
      {
        'auth.password': 'old-password',
        'auth.ui.accessToken': token,
        'auth.ui.refreshToken': 'refresh',
        'custom.headers': '{"X-Proxy":"secret"}',
      },
      failDeletes: true,
    );
    final container = _container(storage);

    final auth = await container
        .read(authCredentialsStoreProvider.future)
        .timeout(const Duration(seconds: 5));
    final headers = await container
        .read(customHttpHeadersProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(auth.uiAccessToken, token);
    expect(headers, {'X-Proxy': 'secret'});
    expect(keychainRefusedThisRun, isFalse);
  });
}
