import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['TSUMIRU_ACCOUNT_TESTBED'];
  test('both live accounts restore only their own verified binding', () async {
    final credentials =
        jsonDecode(await File('$root/credentials.json').readAsString())
            as Map<String, dynamic>;
    await HttpOverrides.runZoned(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        DBKeys.serverUrl.name: 'http://127.0.0.1',
        DBKeys.serverPort.name: 4598,
        DBKeys.serverPortToggle.name: true,
        DBKeys.authType.name: AuthType.uiLogin.index,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      final client = GraphQLClient(
        link: HttpLink('http://127.0.0.1:4598/api/graphql'),
        cache: GraphQLCache(),
        defaultPolicies: DefaultPolicies(
          query: Policies(fetch: FetchPolicy.noCache),
        ),
      );
      final catalogs = <int, String>{};
      for (final role in ['admin', 'reader', 'admin']) {
        final credential = credentials[role] as Map<String, dynamic>;
        await container
            .read(authCoordinatorProvider.notifier)
            .loginUi(
              gqlClient: client,
              username: credential['username'] as String,
              password: credential['password'] as String,
            );
        final state = container.read(authCredentialsStoreProvider).requireValue;
        final binding = state.accountBinding!;
        expect(binding.userId, role == 'admin' ? 1 : 2);
        final previous = catalogs[binding.userId];
        if (previous != null) expect(binding.catalogId, previous);
        catalogs[binding.userId!] = binding.catalogId;
        final restored = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        final saved = await restored.read(authCredentialsStoreProvider.future);
        expect(saved.accountBinding?.userId, binding.userId);
        expect(saved.accountBinding?.catalogId, binding.catalogId);
        restored.dispose();
      }
      expect(catalogs[1], isNot(catalogs[2]));
      await container
          .read(authCredentialsStoreProvider.notifier)
          .clearUiLoginTokens();
      expect(
        container
            .read(authCredentialsStoreProvider)
            .requireValue
            .accountBinding,
        isNull,
      );
    }, createHttpClient: _RealHttp().createHttpClient);
  }, skip: root == null ? 'Requires an isolated account test server' : false);
}
