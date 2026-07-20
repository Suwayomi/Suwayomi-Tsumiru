// A server switch must clear stored credentials so A's secrets never reach B.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final _store = <String, String>{};
  @override
  Future<void> write({required String key, required String? value, iOptions,
      aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    value == null ? _store.remove(key) : _store[key] = value;
  }

  @override
  Future<String?> read({required String key, iOptions, aOptions, lOptions,
          webOptions, mOptions, wOptions}) async =>
      _store[key];

  @override
  Future<void> delete({required String key, iOptions, aOptions, lOptions,
      webOptions, mOptions, wOptions}) async {
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not stubbed');
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(_InMemorySecureStorage()),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  await c.read(authCredentialsStoreProvider.future);
  return c;
}

void main() {
  test('switching host clears credentials; same-host edits keep them',
      () async {
    final c = await _container();
    // Keep providers alive across updates (real watchers would in the app).
    c.listen(serverUrlProvider, (_, __) {}, fireImmediately: true);
    c.listen(credentialsProvider, (_, __) {}, fireImmediately: true);
    final store = c.read(authCredentialsStoreProvider.notifier);
    final serverUrl = c.read(serverUrlProvider.notifier);

    // Establish host A, then seed credentials against it.
    serverUrl.update('http://192.168.1.10:4567');
    await store.savePassword('hunter2');
    await store.saveSimpleLoginCookie('JSESSIONID=abc');
    await c.read(credentialsProvider.notifier).set('Basic abc123');

    // Same host (trailing slash / path change) — credentials survive.
    serverUrl.update('http://192.168.1.10:4567/manga');
    await Future<void>.delayed(Duration.zero);
    var state = await c.read(authCredentialsStoreProvider.future);
    expect(state.password, 'hunter2');
    expect(state.simpleLoginCookie, 'JSESSIONID=abc');
    expect(await c.read(credentialsProvider.future), 'Basic abc123');

    // Different host — every credential cleared, including the Basic header.
    serverUrl.update('http://10.0.0.5:4567');
    await Future<void>.delayed(Duration.zero);
    state = await c.read(authCredentialsStoreProvider.future);
    expect(state.password, isNull);
    expect(state.simpleLoginCookie, isNull);
    expect(await c.read(credentialsProvider.future), isNull);
  });

  test('changing the server port clears credentials too', () async {
    final c = await _container();
    c.listen(serverPortProvider, (_, __) {}, fireImmediately: true);
    final store = c.read(authCredentialsStoreProvider.notifier);
    final port = c.read(serverPortProvider.notifier);

    port.update(4567);
    await store.savePassword('pw');
    port.update(4568); // effective endpoint changed
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(authCredentialsStoreProvider.future)).password, isNull);
  });

  test('a delayed token write with a stale epoch is discarded', () async {
    final c = await _container();
    final store = c.read(authCredentialsStoreProvider.notifier);

    final epochBefore = store.serverEpoch;
    await store.clearAllForServerSwitch(); // simulates a server switch
    // A refresh/worker that started before the switch tries to write back.
    await store.updateUiLoginAccessToken('tokenFromOldServer',
        forEpoch: epochBefore);

    final state = await c.read(authCredentialsStoreProvider.future);
    expect(state.uiAccessToken, isNull);
  });

  test('different port counts as a different host', () async {
    final c = await _container();
    // Keep serverUrlProvider alive across updates (a real watcher would in the app).
    c.listen(serverUrlProvider, (_, __) {}, fireImmediately: true);
    final store = c.read(authCredentialsStoreProvider.notifier);
    final serverUrl = c.read(serverUrlProvider.notifier);

    serverUrl.update('http://host.local:4567');
    await store.savePassword('pw');
    serverUrl.update('http://host.local:4568');
    await Future<void>.delayed(Duration.zero);
    final state = await c.read(authCredentialsStoreProvider.future);
    expect(state.password, isNull);
  });
}
