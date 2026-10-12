import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _FileCacheManager extends Fake implements CacheManager {
  _FileCacheManager(this.fileInfo);

  final FileInfo fileInfo;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.value(fileInfo);
}

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

Future<void> _pumpImage(
  WidgetTester tester,
  FileInfo fileInfo, {
  required bool reduce,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        serverPageCacheManagerProvider.overrideWithValue(
          _FileCacheManager(fileInfo),
        ),
        if (reduce) appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
      ],
      child: MaterialApp(
        builder: (context, child) => ReduceMotionScope(child: child!),
        home: const Scaffold(
          body: ServerImage(
            imageUrl: 'http://server/api/v1/manga/1/page/1',
            size: Size(40, 40),
          ),
        ),
      ),
    ),
  );
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find
        .descendant(
          of: find.byType(ServerImage),
          matching: find.byType(FadeTransition),
        )
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
  fail('the page never finished loading');
}

Future<FileInfo> _loadedPage(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final fileSystem = IOFileSystem('server_image_motion');
    final file = await fileSystem.createFile('page.png');
    await file.writeAsBytes(base64Decode(_onePixelPng));
    return FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 1)),
      'http://server/api/v1/manga/1/page/1',
    );
  }))!;
}

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets('reduced motion draws a loaded page at full opacity at once', (
    tester,
  ) async {
    await _pumpImage(tester, await _loadedPage(tester), reduce: true);

    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(ServerImage),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
  });

  testWidgets(
    'without reduced motion a loaded page is still fading in after one frame',
    (tester) async {
      await _pumpImage(tester, await _loadedPage(tester), reduce: false);

      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(ServerImage),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, lessThan(1));
    },
  );
}
