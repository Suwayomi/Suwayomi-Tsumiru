@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache_manager_stub.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

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

  test(
    'a load pending when the cover cache is replaced still completes',
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
      final pending = first.getSingleFile(_pngDataUrl);
      (container.read(serverUrlProvider.notifier) as _ServerUrl).select(
        'https://example.test',
      );
      expect(container.read(coverCacheManagerProvider), isNot(same(first)));
      expect(await (await pending).readAsBytes(), _pngBytes);
    },
  );

  testWidgets(
    'a cover that failed under a replaced cache loads under the new one',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          _coverManagerSource.overrideWith(
            () => _CoverManagerSource(
              _FixedCacheManager(error: http.ClientException('offline')),
            ),
          ),
          coverCacheManagerProvider.overrideWith(
            (ref) => ref.watch(_coverManagerSource),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ServerImage(
                imageUrl: '/api/v1/manga/1/thumbnail',
                size: Size(40, 40),
              ),
            ),
          ),
        ),
      );
      expect(await _settle(tester, _showsBrokenImage), isTrue);

      container
          .read(_coverManagerSource.notifier)
          .replace(_FixedCacheManager(bytes: _pngBytes));
      await tester.pump();
      expect(await _settle(tester, _showsDecodedImage), isTrue);
    },
  );
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
final _pngBytes = Uint8List.fromList(base64Decode(_onePixelPng));
final _pngDataUrl = 'data:image/png;base64,$_onePixelPng';

class _FixedCacheManager extends Fake implements CacheManager {
  _FixedCacheManager({this.bytes, this.error});

  final Uint8List? bytes;
  final Object? error;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    if (error != null) return Stream.error(error!);
    final file = MemoryFileSystem().file('cover')..writeAsBytesSync(bytes!);
    return Stream.value(
      FileInfo(file, FileSource.Online, DateTime(2100), key ?? url),
    );
  }
}

class _CoverManagerSource extends Notifier<CacheManager> {
  _CoverManagerSource(this.initial);

  final CacheManager initial;

  @override
  CacheManager build() => initial;

  void replace(CacheManager manager) => state = manager;
}

final _coverManagerSource = NotifierProvider<_CoverManagerSource, CacheManager>(
  () => _CoverManagerSource(_FixedCacheManager()),
);

Future<bool> _settle(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (done()) return true;
  }
  return false;
}

bool _showsBrokenImage() =>
    find.byIcon(Icons.broken_image_rounded).evaluate().isNotEmpty;

bool _showsDecodedImage() => find
    .descendant(of: find.byType(ServerImage), matching: find.byType(RawImage))
    .evaluate()
    .isNotEmpty;
