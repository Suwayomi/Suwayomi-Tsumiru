import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/credential_snapshot.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_io.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/tracking/data/native_tracker_oauth.dart';
import 'package:tsumiru/src/features/tracking/domain/tracker_oauth_origin.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import 'oauth_test_storage.dart';

// Distinct handles isolate the snapshot caches while sharing the platform store.
class _EngineStorage extends OAuthTestStorage {
  _EngineStorage(this.backing);
  final OAuthTestStorage backing;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => backing.read(key: key);
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
  }) => backing.write(key: key, value: value);
  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => backing.delete(key: key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const binding = AccountBinding(
    address: 'https://server.test',
    userId: 2,
    username: 'Reader',
    catalogId: 'catalog-reader',
  );
  late SharedPreferences prefs;
  late OAuthTestStorage backing;
  late int mutations;
  late String opened;
  late String path;

  setUp(() async {
    debugResetKeychainRefusal();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backing = OAuthTestStorage();
    backing.values.addAll({
      kUiAccessTokenSecureKey: 'A',
      kUiRefreshTokenSecureKey: 'R',
      kUiAccountBindingSecureKey: binding.encode(
        accessToken: 'A',
        refreshToken: 'R',
      ),
    });
    mutations = 0;
    opened = '';
    path =
        '${(await Directory.systemTemp.createTemp('oauth-engine-test-')).path}/pending.sqlite';
  });
  Future<({ProviderContainer container, NativeTrackerOAuth handler})>
  engine() async {
    final storage = _EngineStorage(backing);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureStorageProvider.overrideWithValue(storage),
        pendingTrackerOAuthStoreProvider.overrideWithValue(
          SqlitePendingTrackerOAuthStore(path: path),
        ),

      ],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    final auth = container.read(authCredentialsStoreProvider.notifier);
    final handler = NativeTrackerOAuth(
      pending: container.read(pendingTrackerOAuthStoreProvider),
      captureSession: auth.captureSession,
      readOrigin: (current) async {
        final state = await container.read(authCredentialsStoreProvider.future);
        if (!current()) return null;
        return trackerOAuthOrigin(
          mode: AuthType.uiLogin,
          configuredServer: binding.address,
          username: binding.username,
          binding: state.accountBinding,
        );
      },
      loginOAuth: (_, _) async => mutations++,
      onSuccess: () {},
      now: () => DateTime.utc(2026, 10, 21),
    );
    return (container: container, handler: handler);
  }

  Future<void> begin(NativeTrackerOAuth handler) async {
    expect(
      await handler.begin(
        authUrl: 'https://tracker.test/auth?client_id=public',
        trackerId: 1,
        trackerName: 'AniList',
        launch: (url) async => opened = url,
      ),
      TrackerOAuthBeginOutcome.started,
    );
  }

  Uri callback() => Uri(
    scheme: 'tsumiru',
    host: 'tracker-oauth',
    queryParameters: {
      'access_token': 'example-token',
      'state': Uri.parse(opened).queryParameters['state']!,
    },
  );

  test(
    'an independent stale credential writer cannot resurrect a consumed OAuth request',
    () async {
      final a = await engine();
      await begin(a.handler);
      final uri = callback();
      final b = await engine();
      expect(identical(a.handler.pending, b.handler.pending), isFalse);
      expect(await b.handler.pending.read(), isNotNull);
      expect(
        await b.handler.handleCallback(uri),
        TrackerOAuthOutcome.succeeded,
      );
      expect(mutations, 1);
      expect(await b.handler.pending.read(), isNull);
      expect(await a.handler.pending.read(), isNull);

      final authA = a.container.read(authCredentialsStoreProvider.notifier);
      expect(
        await authA.refreshUiLoginTokens(
          accessToken: 'A2',
          refreshToken: 'R2',
          originalRefreshToken: 'R',
          forEpoch: authA.serverEpoch,
        ),
        isTrue,
      );
      final c = await engine();
      await c.handler.handleCallback(uri);
      expect(mutations, 1);
    },
  );

  test(
    'independent loaded snapshots cannot both consume the same OAuth callback',
    () async {
      final a = await engine();
      await begin(a.handler);
      final b = await engine();
      final c = await engine();
      expect(identical(b.handler.pending, c.handler.pending), isFalse);
      expect(await b.handler.pending.read(), isNotNull);
      expect(await c.handler.pending.read(), isNotNull);
      final uri = callback();
      await Future.wait([
        b.handler.handleCallback(uri),
        c.handler.handleCallback(uri),
      ]);
      expect(mutations, 1);
    },
  );
}
