@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_stub.dart';

class _ServerUrl extends ServerUrl {
  @override
  String? build() => 'http://localhost:4567';

  void select(String value) => state = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final url in [
    'localhost:4567',
    'example.test',
    '/server',
    'http:relative',
  ]) {
    test('invalid server URL does not break the image cache: $url', () async {
      SharedPreferences.setMockInitialValues({
        DBKeys.serverUrl.name: url,
        DBKeys.serverPortToggle.name: false,
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final manager = container.read(coverCacheManagerProvider);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await manager.putFile('cached-cover', bytes);
      expect(
        await (await manager.getSingleFile('cached-cover')).readAsBytes(),
        bytes,
      );
    });
  }

  test(
    'invalid image URL fails as a request, not an origin StateError',
    () async {
      final manager = createCoverCacheManager(
        serverOrigin: 'http://localhost:4567',
      );
      addTearDown(manager.dispose);
      await expectLater(
        manager.getSingleFile('localhost:4567/thumbnail'),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test(
    'endpoint replacement has a new memory cache shared by pages and covers',
    () async {
      SharedPreferences.setMockInitialValues({
        DBKeys.serverPortToggle.name: false,
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          serverUrlProvider.overrideWith(_ServerUrl.new),
        ],
      );
      addTearDown(container.dispose);
      final first = container.read(coverCacheManagerProvider);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await first.putFile('cached-cover', bytes);
      expect(
        await (await container
                .read(serverPageCacheManagerProvider)
                .getSingleFile('cached-cover'))
            .readAsBytes(),
        bytes,
      );
      (container.read(serverUrlProvider.notifier) as _ServerUrl).select(
        'https://example.test',
      );
      final replacement = container.read(coverCacheManagerProvider);
      expect(replacement, isNot(same(first)));
      expect(await replacement.getFileFromCache('cached-cover'), isNull);
      expect(container.read(serverPageCacheManagerProvider), same(replacement));
    },
  );
}
