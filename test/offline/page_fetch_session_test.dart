import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final status in [401, 403, 500, 502, 503, 504]) {
    test('page HTTP $status keeps its failure classification', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        DBKeys.serverUrl.name: 'https://server.example',
        DBKeys.serverPortToggle.name: false,
        DBKeys.authType.name: AuthType.none.index,
      });
      final client = MockClient(
        (request) async => http.Response('unavailable', status),
      );
      addTearDown(client.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          offlinePageClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      final fetch = Provider(
        (ref) =>
            () => fetchOfflinePageBytes(
              ref,
              '/page',
              isCurrentSession: () => true,
            ),
      );
      final Matcher expected = switch (status) {
        401 => isA<PageAuthException>(),
        403 => isA<AccountPermissionDenied>(),
        500 => allOf(isA<Exception>(), isNot(isA<PageOfflineException>())),
        _ => isA<PageOfflineException>().having(
          (error) => error.reason,
          'reason',
          contains('HTTP $status'),
        ),
      };
      await expectLater(container.read(fetch)(), throwsA(expected));
    });
  }

  test(
    'page requests and delayed bytes stay with their original session',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth.ui.accessToken': 'A',
        'auth.ui.refreshToken': 'R-A',
      });
      SharedPreferences.setMockInitialValues({
        DBKeys.serverUrl.name: 'https://server.example',
        DBKeys.serverPortToggle.name: false,
        DBKeys.authType.name: AuthType.uiLogin.index,
      });
      final received = Completer<void>();
      final release = Completer<void>();
      final sent = <String?>[];
      final client = MockClient((request) async {
        final token = request.url.queryParameters['token'];
        sent.add(token);
        if (token == 'A') {
          received.complete();
          await release.future;
        }
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          offlinePageClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      final fetchProvider = Provider((ref) {
        final current = watchAuthSession(ref);
        return () =>
            fetchOfflinePageBytes(ref, '/page', isCurrentSession: current);
      });
      await container.read(authCredentialsStoreProvider.future);
      final oldFetch = container.read(fetchProvider);
      final pending = oldFetch();
      final rejection = expectLater(pending, throwsStateError);
      await received.future;
      await container
          .read(authCredentialsStoreProvider.notifier)
          .saveUiLoginTokens(accessToken: 'B', refreshToken: 'R-B');
      release.complete();
      await rejection;
      await expectLater(oldFetch(), throwsStateError);
      final bytes = await container.read(fetchProvider)();
      expect(bytes.bytes, [1, 2, 3]);
      expect(sent, ['A', 'B']);
    },
  );
}
