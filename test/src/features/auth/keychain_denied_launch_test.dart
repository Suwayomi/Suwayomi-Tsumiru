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
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

/// A keychain that refuses every read, and optionally every write and delete.
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

bool _invalidated() =>
    _prefs.getBool(DBKeys.authCredentialsInvalidated.name) ?? false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    debugResetKeychainRefusal();
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  test(
    'a refused keychain is asked once and every credential reads absent',
    () async {
      final storage = _DeniedStorage();
      final c = _container(storage);

      final auth = await c
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      final basic = await c
          .read(credentialsProvider.future)
          .timeout(const Duration(seconds: 5));
      final headers = await c
          .read(customHttpHeadersProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(storage.reads, 1);
      expect(auth.uiAccessToken, isNull);
      expect(auth.uiRefreshToken, isNull);
      expect(auth.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(headers, isEmpty);

      c.invalidate(credentialsProvider);
      await c.read(credentialsProvider.future);
      expect(storage.reads, 1, reason: 'a refused keychain is not asked again');
    },
  );

  testWidgets(
    'a sign-in whose writes are refused still works after the session rebuild',
    (tester) async {
      final storage = _DeniedStorage(failWrites: true);
      final prefs = await _uiLoginPreferences();
      final chain = _UiLoginChain();
      late WidgetRef ref;
      late _RecordingToast toast;

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
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final first = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await first
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));

      await performSignIn(
        ref,
        authType: AuthType.uiLogin,
        serverBaseUrl: 'http://127.0.0.1',
        username: 'reader',
        password: 'password',
      ).timeout(const Duration(seconds: 5));

      // The sign-in restarts the session container. The new container must
      // still see the sign-in: it lives in memory, not in a keychain that
      // refused the save.
      final restarted = _sessionContainer(storage, prefs, chain);
      final state = await restarted
          .read(authCredentialsStoreProvider.future)
          .timeout(const Duration(seconds: 5));
      expect(state.uiAccessToken, chain.token);
      expect(state.uiRefreshToken, 'test-refresh');
      expect(storage.reads, 1);

      final token = await restarted
          .read(authCoordinatorProvider.notifier)
          .usableUiAccessToken(
            gqlClient: () => throw StateError('unexpected refresh'),
            trigger: 'test',
          )
          .timeout(const Duration(seconds: 5));
      expect(token, chain.token);
      restarted.dispose();

      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'a refused replacement signs out next launch instead of restoring the old account',
    () async {
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-access',
        'auth.ui.refreshToken': 'old-refresh',
      };
      final storage = _FlakyStorage(backing)..failWrites = true;
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
          );

      // The write was refused: the old account is still in storage.
      expect(backing['auth.ui.accessToken'], 'old-access');
      expect(_invalidated(), isTrue);

      // Next launch, keychain working again. The unknown-on-disk state must
      // not be handed to the user as the previous account.
      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final state = await restarted.read(authCredentialsStoreProvider.future);
      expect(state.uiAccessToken, isNull);
      expect(state.uiRefreshToken, isNull);
      expect(backing, isEmpty);
      expect(_invalidated(), isFalse);
    },
  );

  test(
    'a switch whose credential delete is refused cannot reuse the old sign-in',
    () async {
      final backing = <String, String>{
        'auth.ui.accessToken': _testToken(),
        'auth.ui.refreshToken': 'old-refresh',
        'auth.simple.cookie': 'JSESSIONID=old',
        kBasicCredentialsSecureKey: 'Basic old',
      };
      final first = _container(_FlakyStorage(backing, failDeletes: true));
      final before = await first.read(authCredentialsStoreProvider.future);
      expect(before.uiAccessToken, isNotNull);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      expect(_invalidated(), isTrue);
      expect(backing, isNotEmpty);

      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final auth = await restarted.read(authCredentialsStoreProvider.future);
      final basic = await restarted.read(credentialsProvider.future);

      expect(auth.uiAccessToken, isNull);
      expect(auth.uiRefreshToken, isNull);
      expect(auth.simpleLoginCookie, isNull);
      expect(basic, isNull);
      expect(backing, isEmpty);
      expect(_invalidated(), isFalse);
    },
  );

  test(
    'a deferred Basic migration cannot restore a credential the user cleared',
    () async {
      // The migration was deferred because the keychain refused, so the legacy
      // copy is still there when the user switches server.
      SharedPreferences.setMockInitialValues({'basicCredentials': 'Basic old'});
      _prefs = await SharedPreferences.getInstance();
      final backing = <String, String>{kBasicCredentialsSecureKey: 'Basic old'};
      final first = _container(_FlakyStorage(backing, failDeletes: true));
      await first.read(credentialsProvider.future);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      expect(_invalidated(), isTrue);
      expect(_prefs.getString('basicCredentials'), isNull);

      // Next launch, keychain working again: the invalidation cleanup runs,
      // and the migration must not re-import the cleared sign-in behind it.
      debugResetKeychainRefusal();
      final nextStorage = _FlakyStorage(backing);
      await migrateBasicAuthCredentials(prefs: _prefs, secure: nextStorage);
      final restarted = _container(nextStorage);
      expect(await restarted.read(credentialsProvider.future), isNull);
      expect(backing[kBasicCredentialsSecureKey], isNull);
    },
  );

  test(
    'a sign-in that saves after a refused one is read next launch',
    () async {
      final backing = <String, String>{
        'auth.ui.accessToken': 'old-access',
        'auth.ui.refreshToken': 'old-refresh',
      };
      final storage = _FlakyStorage(backing)..failWrites = true;
      final first = _container(storage);
      await first.read(authCredentialsStoreProvider.future);

      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(accessToken: 'refused-access', refreshToken: 'r');
      expect(_invalidated(), isTrue);

      storage.failWrites = false;
      final token = _testToken();
      await first
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(accessToken: token, refreshToken: 'saved-refresh');
      expect(_invalidated(), isFalse);
      expect(backing['auth.ui.accessToken'], token);

      debugResetKeychainRefusal();
      final restarted = _container(_FlakyStorage(backing));
      final state = await restarted.read(authCredentialsStoreProvider.future);
      expect(state.uiAccessToken, token);
      expect(state.uiRefreshToken, 'saved-refresh');
    },
  );

  test('proxy headers read at startup survive a later refused write', () async {
    final storage = _FlakyStorage({
      'custom.headers': '{"CF-Access-Client-Id":"abc"}',
    });
    final c = _container(storage);
    expect(await c.read(customHttpHeadersProvider.future), {
      'CF-Access-Client-Id': 'abc',
    });

    storage.failWrites = true;
    await c
        .read(authCredentialsStoreProvider.notifier)
        .saveSimpleLoginCookie('JSESSIONID=x');
    expect(_invalidated(), isTrue);

    c.invalidate(customHttpHeadersProvider);
    expect(await c.read(customHttpHeadersProvider.future), {
      'CF-Access-Client-Id': 'abc',
    });
  });

  test('account invalidation keeps proxy headers', () async {
    final backing = <String, String>{
      'auth.ui.accessToken': 'old-access',
      'auth.ui.refreshToken': 'old-refresh',
      'custom.headers': '{"CF-Access-Client-Id":"abc"}',
    };
    final first = _container(_FlakyStorage(backing, failDeletes: true));
    await first.read(authCredentialsStoreProvider.future);

    // The sign-out cannot delete the stored tokens, so the marker says the
    // account state is unknown.
    await first
        .read(authCredentialsStoreProvider.notifier)
        .clearUiLoginTokens();
    expect(_invalidated(), isTrue);

    // Next launch, keychain working again: the account cleanup must not take
    // the endpoint's proxy headers with it.
    debugResetKeychainRefusal();
    final restarted = _container(_FlakyStorage(backing));
    final auth = await restarted.read(authCredentialsStoreProvider.future);
    expect(auth.uiAccessToken, isNull);
    expect(await restarted.read(customHttpHeadersProvider.future), {
      'CF-Access-Client-Id': 'abc',
    });
    expect(backing['custom.headers'], isNotNull);
  });

  test(
    'a refused Basic migration is retried next launch instead of lost',
    () async {
      SharedPreferences.setMockInitialValues({'basicCredentials': 'Basic abc'});
      _prefs = await SharedPreferences.getInstance();
      final token = _testToken();
      final backing = <String, String>{
        'auth.simple.cookie': 'JSESSIONID=abc123',
        'auth.ui.accessToken': token,
        'auth.ui.refreshToken': 'refresh',
        'custom.headers': '{"CF-Access-Client-Id":"abc"}',
      };

      // Launch 1: the keychain reads work, but the migration's write is
      // refused. The legacy preference stays as the only durable copy, so the
      // account is not marked invalidated.
      await migrateBasicAuthCredentials(
        prefs: _prefs,
        secure: _FlakyStorage(backing)..failWrites = true,
      );
      expect(_prefs.getString('basicCredentials'), 'Basic abc');
      expect(_invalidated(), isFalse);

      // Launch 2, keychain working again: the migration retries and the login
      // survives, with the credentials already in secure storage.
      debugResetKeychainRefusal();
      final nextStorage = _FlakyStorage(backing);
      await migrateBasicAuthCredentials(prefs: _prefs, secure: nextStorage);

      expect(_prefs.getString('basicCredentials'), isNull);
      expect(backing[kBasicCredentialsSecureKey], 'Basic abc');
      final restarted = _container(nextStorage);
      expect(await restarted.read(credentialsProvider.future), 'Basic abc');
      final auth = await restarted.read(authCredentialsStoreProvider.future);
      expect(auth.simpleLoginCookie, 'JSESSIONID=abc123');
      expect(auth.uiAccessToken, token);
      expect(auth.uiRefreshToken, 'refresh');
      expect(await restarted.read(customHttpHeadersProvider.future), {
        'CF-Access-Client-Id': 'abc',
      });
    },
  );

  test('a refused keychain never creates a record key', () async {
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
}
