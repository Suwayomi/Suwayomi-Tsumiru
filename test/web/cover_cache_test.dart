@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invalid server URLs do not break the image cache', () async {
    for (final url in [
      'localhost:4567',
      'example.test',
      '/server',
      'http:relative',
    ]) {
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
      await manager.putFile('cached-cover-$url', bytes);
      expect(
        await (await manager.getSingleFile('cached-cover-$url')).readAsBytes(),
        bytes,
        reason: url,
      );
    }

    // An invalid image URL fails as a request, not an origin StateError.
    final manager = createCoverCacheManager(
      serverOrigin: 'http://localhost:4567',
    );
    addTearDown(manager.dispose);
    await expectLater(
      manager.getSingleFile('localhost:4567/thumbnail'),
      throwsA(isA<http.ClientException>()),
    );
  });
}
