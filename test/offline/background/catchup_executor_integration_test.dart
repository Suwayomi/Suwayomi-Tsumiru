import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_download_executor.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';
import 'package:tsumiru/src/features/offline/data/offline_types.dart';
import 'package:workmanager_android/workmanager_android.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late HttpServer server;
  late CatchupStateStore state;
  late NotificationWorkerConfig config;
  late BackgroundCompletionLog log;
  late List<int> pages;
  late int requests;
  late bool holdPage;
  late bool failPage;
  late List<int> resolvedPages;
  late int serverChapterCount;
  late String serverIdentity;
  late Map<int, List<String>> pageUrls;
  late Completer<void> pageRequested;
  late Completer<void> releasePage;
  const token = BackgroundTokenRecord(gen: 0, authType: 'none');
  final broker = TokenBroker(
    read: () async => token,
    write: (_) async {},
    refreshFn: (_) async => (tokens: null, transient: false),
  );

  Future<bool> run() => HttpOverrides.runZoned(
    () => runCatchupDownloads(
      catchupStore: state,
      config: config,
      record: () => token,
      broker: broker,
    ),
    createHttpClient: _RealHttpOverrides().createHttpClient,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('catchup-integration-');
    pages = [];
    requests = 0;
    holdPage = false;
    failPage = false;
    resolvedPages = [];
    serverChapterCount = 30;
    serverIdentity = 'catalog-uuid';
    pageUrls = {};
    pageRequested = Completer<void>();
    releasePage = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (request.method == 'GET') {
        final id = int.parse(request.uri.pathSegments.last.split('.').first);
        pages.add(id);
        if (!pageRequested.isCompleted) pageRequested.complete();
        if (holdPage) await releasePage.future;
        if (failPage) request.response.statusCode = 500;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([1, 2, 3]);
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final query = body['query'] as String;
        final Object data;
        if (query.contains('OfflineServerIdentity')) {
          data = {
            'metas': {
              'nodes': [
                {'value': serverIdentity},
              ],
            },
          };
        } else if (query.contains('MangaChapters')) {
          data = {
            'chapters': {
              'nodes': List.generate(
                serverChapterCount,
                (index) => {
                  'id': index + 1,
                  'name': 'Chapter ${index + 1}',
                  'sourceOrder': index,
                  'chapterNumber': index + 1,
                  'isRead': false,
                  'isBookmarked': false,
                  'isDownloaded': true,
                  'pageCount': 1,
                },
              ),
            },
          };
        } else {
          expect(query, contains('GetChapterPages'));
          final id = (body['variables'] as Map)['input']['chapterId'];
          resolvedPages.add(id as int);
          data = {
            'fetchChapterPages': {
              'pages': pageUrls[id] ?? ['/page/$id.jpg'],
            },
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': data}));
      }
      await request.response.close();
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return tmp.path;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        expect(call.method, 'check');
        return ['wifi'];
      },
    );
    WorkmanagerAndroid.registerWith();
    for (final method in ['registerPeriodicTask', 'cancelByUniqueName']) {
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.$method',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
    }
    final base = 'http://127.0.0.1:${server.port}';
    final address = serverAddress(baseUrl: base, port: null, addPort: false);
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog-uuid',
      'offlineLastServerId': 'catalog-uuid',
      'offlineLastServerAddress': address,
    });
    state = await CatchupStateStore.open();
    await state.setEnabled(false);
    await state.setDownloadEnabled(false);
    config = NotificationWorkerConfig(
      serverId: base,
      endpoint: NotificationEndpoint(baseUrl: base, addPort: false),
      newChaptersEnabled: false,
      includedCategoryIds: const {},
      excludedCategoryIds: const {},
      hideContent: false,
      catalogServerId: 'catalog-uuid',
      verifiedAddress: address,
    );
    await (await NotificationStateStore.open()).writeConfig(config);
    await state.writeSpec(
      CatchupWorkSpec(
        serverId: 'catalog-uuid',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: const [],
        queuedChapters: List.generate(
          30,
          (index) => QueuedChapterSpec(
            chapterId: index + 1,
            mangaId: 1,
            generation: 0,
          ),
        ),
      ),
    );
    log = BackgroundCompletionLog(
      File('${tmp.path}/offline/.bg_completion.log'),
    );
  });

  tearDown(() async {
    if (!releasePage.isCompleted) releasePage.complete();
    await server.close(force: true);
  });

  Future<void> enableOverlap({
    int queuedCount = 1,
    Set<int> failedChapterIds = const {},
    OfflineKeepRule keepRule = OfflineKeepRule.all,
  }) async {
    await state.setEnabled(true);
    await state.setDownloadEnabled(true);
    await state.writeSpec(
      CatchupWorkSpec(
        serverId: 'catalog-uuid',
        wifiOnly: true,
        storageCapEnabled: false,
        storageCapBytes: 0,
        manga: [
          CatchupMangaSpec(
            mangaId: 1,
            keepRule: keepRule,
            keepUnreadCount: 3,
            onDeviceChapterIds: {},
            pinnedChapterIds: {},
            failedChapterIds: failedChapterIds,
          ),
        ],
        queuedChapters: List.generate(
          queuedCount,
          (index) => QueuedChapterSpec(
            chapterId: index + 1,
            mangaId: 1,
            generation: 0,
          ),
        ),
      ),
    );
  }

  test(
    'resumed bytes count once and crossing cap blocks the next fresh chapter',
    () async {
      final store = IoOfflinePageStore(OfflinePaths('${tmp.path}/offline'));
      await store.beginChapter(
        1,
        1,
        const ChapterManifest(generation: 0, indices: [0, 1]),
      );
      await store.writePage(1, 1, 0, List.filled(100, 1), 'jpg');
      pageUrls[1] = ['/page/1.jpg', '/page/1.jpg'];
      var initialBytes = 0;
      await for (final entry in Directory(
        '${tmp.path}/offline/1',
      ).list(recursive: true)) {
        if (entry is File) initialBytes += await entry.length();
      }
      await state.writeSpec(
        CatchupWorkSpec(
          serverId: 'catalog-uuid',
          wifiOnly: true,
          storageCapEnabled: true,
          storageCapBytes: initialBytes + 10,
          manga: const [],
          queuedChapters: List.generate(
            3,
            (index) => QueuedChapterSpec(
              chapterId: index + 1,
              mangaId: 1,
              generation: 0,
            ),
          ),
        ),
      );
      expect(await run(), isTrue);
      expect(pages, [1, 2]);
      expect(
        (await log.parse()).whereType<ChapterEntry>().map(
          (entry) => entry.chapterId,
        ),
        [1, 2],
      );
      expect(await store.readManifest(1, 3), isNull);
    },
  );

  test(
    'keep three skips a failed chapter when selecting its unread window',
    () async {
      serverChapterCount = 5;
      await enableOverlap(
        queuedCount: 0,
        failedChapterIds: {1},
        keepRule: OfflineKeepRule.nUnread,
      );
      expect(await run(), isTrue);
      expect(pages, [2, 3, 4]);
      expect(resolvedPages, [2, 3, 4]);
    },
  );

  test('a different live server identity prevents chapter requests', () async {
    serverIdentity = 'other-catalog';
    await run();
    expect(requests, 1);
    expect(resolvedPages, isEmpty);
    expect(pages, isEmpty);
  });

  test(
    'published failed chapters stay excluded after terminal log replay',
    () async {
      serverChapterCount = 3;
      await enableOverlap(queuedCount: 0, failedChapterIds: {1});
      expect(await log.parse(), isEmpty);
      expect(await run(), isTrue);
      expect(pages, [2, 3]);
      expect(resolvedPages, [2, 3]);
      expect(
        (await log.parse()).whereType<AdoptChapterEntry>().map(
          (entry) => entry.chapterId,
        ),
        [2, 3],
      );
    },
  );

  test(
    'same endpoint reauthorization rejects the captured old identity epoch',
    () async {
      await state.setIdentityAuthorized(false);
      await state.setIdentityAuthorized(true);
      expect(state.identityAuthorized, isTrue);
      expect(state.identityEpoch, greaterThan(config.identityEpoch));
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  test(
    'queued hard failure is not attempted again through the keep rule',
    () async {
      serverChapterCount = 1;
      failPage = true;
      await enableOverlap();
      expect(await run(), isTrue);
      expect(resolvedPages, [1]);
      expect(state.readLedger('catalog-uuid').queuedDownloadRetries, {
        '1:0': 1,
      });
      expect(state.readLedger('catalog-uuid').downloadRetries, isEmpty);
      expect((await log.parse()).whereType<AdoptChapterEntry>(), isEmpty);
    },
  );

  test(
    'exhausted queued generation cannot retry through the keep rule',
    () async {
      serverChapterCount = 1;
      await enableOverlap();
      await state.writeLedger(
        'catalog-uuid',
        const CatchupLedger(queuedDownloadRetries: {'1:0': 5}),
      );
      for (var wake = 0; wake < 2; wake++) {
        expect(await run(), isTrue);
      }
      expect(resolvedPages, isEmpty);
      expect(pages, isEmpty);
      final errors = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(errors.length, 1);
      expect(errors.single.status, 'error');
      expect(errors.single.generation, 0);
      expect(state.readLedger('catalog-uuid').downloadRetries, isEmpty);
    },
  );

  test(
    'queued and keep-rule downloads share the ten-chapter allowance',
    () async {
      await enableOverlap(queuedCount: 4);
      expect(await run(), isTrue);
      expect(pages.length, 10);
      expect(pages.toSet().length, 10);
      final entries = await log.parse();
      expect(entries.whereType<ChapterEntry>().length, 4);
      expect(entries.whereType<AdoptChapterEntry>().length, 6);
    },
  );

  test(
    'three real executor wakes finish thirty queued chapters with catchup disabled',
    () async {
      for (var wake = 1; wake <= 3; wake++) {
        expect(await run(), isTrue);
        expect(pages.length, wake * 10);
        expect(pages.toSet().length, wake * 10);
      }
      final successes = (await log.parse()).whereType<ChapterEntry>().toList();
      expect(successes.length, 30);
      expect(
        successes.every(
          (entry) => entry.status == 'downloaded' && entry.generation == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'live pause blocks a previously published queue before network work',
    () async {
      await (await SharedPreferences.getInstance()).setBool(
        'offlineDownloadsPaused',
        true,
      );
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  test(
    'revoked identity blocks the published queue before network work',
    () async {
      await state.setIdentityAuthorized(false);
      expect(await run(), isTrue);
      expect(requests, 0);
    },
  );

  test(
    'yield aborts a slow page and releases ownership without spending retries',
    () async {
      holdPage = true;
      final running = run();
      await pageRequested.future.timeout(const Duration(seconds: 5));
      final contender = BackgroundDownloadLock(
        File('${tmp.path}/offline/.bg_lock'),
      );
      expect(await contender.acquire('test'), isFalse);
      await contender.requestYield();
      expect(await running.timeout(const Duration(seconds: 5)), isTrue);
      expect(await contender.acquire('test'), isTrue);
      await contender.release();
      expect(state.readLedger('catalog-uuid').queuedDownloadRetries, isEmpty);
      expect((await log.parse()).whereType<ChapterEntry>(), isEmpty);
      releasePage.complete();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final files = await Directory('${tmp.path}/offline')
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('.jpg'))
          .toList();
      expect(files, isEmpty);
      expect(pages, [1]);
    },
  );
}
