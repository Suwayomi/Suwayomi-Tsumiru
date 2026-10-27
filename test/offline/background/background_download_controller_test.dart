import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/background_work_order.dart';
import 'package:tsumiru/src/features/offline/data/background/download_task_handler.dart';
import 'package:tsumiru/src/features/offline/data/background/foreground_service_gateway.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_stall.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:workmanager/workmanager.dart';

import '../../helpers/offline_test_db.dart';

class _RealHttpOverrides extends HttpOverrides {}

class FakeService extends ForegroundServiceGateway {
  DataCallback? callback;
  bool running = false;
  int starts = 0;
  Future<ServiceRequestResult> Function()? onStart;
  Future<void> Function()? onPermission;
  Future<bool> Function()? onRunning;
  final values = <String, String>{};
  final messages = <Object>[];
  final reads = <String>[];

  @override
  Future<bool> get isRunningService async =>
      await (onRunning?.call() ?? Future.value(running));
  @override
  Future<ServiceRequestResult> start() async {
    starts++;
    final result =
        await (onStart?.call() ?? Future.value(const ServiceRequestSuccess()));
    if (result is ServiceRequestSuccess) running = true;
    return result;
  }

  @override
  Future<ServiceRequestResult> stop() async {
    running = false;
    return const ServiceRequestSuccess();
  }

  @override
  void send(Object data) => messages.add(data);
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> ensureNotificationPermission() async {
    await onPermission?.call();
  }

  @override
  void addCallback(DataCallback callback) {
    this.callback = callback;
  }

  @override
  void removeCallback(DataCallback callback) {}
}

class DelayedManifestStore extends IoOfflinePageStore {
  DelayedManifestStore(super.paths);
  Future<ChapterManifest?> Function()? onManifest;
  @override
  Future<ChapterManifest?> readManifest(int mangaId, int chapterId) =>
      onManifest?.call() ?? super.readManifest(mangaId, chapterId);
}

/// Stands in for the OS scheduler: without it, reconcileBackgroundSchedule
/// reaches the host's real workmanager plugin — systemd user units on Linux,
/// none at all on Windows (UnimplementedError).
class _NoopSchedule extends WorkmanagerPlatform {
  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {}

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    String? tag,
    ExistingWorkPolicy? existingWorkPolicy,
    Duration? initialDelay,
    Constraints? constraints,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    Map<String, dynamic>? inputData,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {}

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineDatabase db;
  late ProviderContainer container;
  late BackgroundDownloadController controller;
  late FakeService service;
  late SharedPreferences prefs;
  late List<String?> notices;
  late List<ConnectivityResult> network;
  late DelayedManifestStore pageStore;
  late Future<void> Function() publishQueue;
  late Timer Function(Duration, void Function()) makeTimer;
  late List<bool> silentNotices;
  late bool android;
  late bool offlineEnabled;
  late StreamController<List<ConnectivityResult>> connectionChanges;
  late WorkmanagerPlatform previousSchedule;

  setUp(() async {
    Workmanager();
    previousSchedule = WorkmanagerPlatform.instance;
    WorkmanagerPlatform.instance = _NoopSchedule();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'offlineCatalogServerId': 'catalog-A',
    });
    prefs = await SharedPreferences.getInstance();
    db = testOfflineDatabase();
    final tmp = await Directory.systemTemp.createTemp('download-start-test');
    final paths = OfflinePaths(tmp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tmp.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    pageStore = DelayedManifestStore(paths);
    service = FakeService();
    notices = [];
    silentNotices = [];
    publishQueue = () async {};
    makeTimer = Timer.new;
    network = [ConnectivityResult.wifi];
    android = true;
    offlineEnabled = true;
    connectionChanges = StreamController<List<ConnectivityResult>>.broadcast();
    addTearDown(connectionChanges.close);
    final controllerOverride = backgroundDownloadControllerProvider
        .overrideWith(
          (ref) => BackgroundDownloadController(
            ref,
            gateway: service,
            isAndroid: () => android,
            identityAllowed: () => true,
            publishQueue: () => publishQueue(),
            timer: (duration, callback) => makeTimer(duration, callback),
            connectivity: () async => network,
            connectivityChanges: connectionChanges.stream,
            notifyStall: (reason, {required silent}) async {
              notices.add(reason);
              silentNotices.add(silent);
            },
          ),
        );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        controllerOverride,
        offlineDatabaseProvider.overrideWith((ref) {
          if (!offlineEnabled) throw StateError('Offline storage unavailable');
          return db;
        }),
        serverInstanceIdProvider.overrideWith((ref) {
          ref.watch(serverUrlProvider);
          return Completer<String>().future;
        }),
        offlinePathsProvider.overrideWith((ref) {
          if (!offlineEnabled) throw StateError('Offline storage unavailable');
          return paths;
        }),
        offlinePageStoreProvider.overrideWithValue(pageStore),
        offlineEnabledProvider.overrideWith((ref) => offlineEnabled),
        offlineActiveProvider.overrideWith((ref) => true),
      ],
    );
    controller = container.read(backgroundDownloadControllerProvider);
    await db.upsertMangaMetadata(id: 1, title: 'M', updatedAt: DateTime(2026));
    await db.upsertChapterMetadata(
      id: 5,
      mangaId: 1,
      name: 'C',
      chapterIndex: 0,
      isRead: false,
      lastPageRead: 0,
      isBookmarked: false,
      serverIsDownloaded: true,
      pageCount: 2,
      updatedAt: DateTime(2026),
    );
    await db.setChapterDeviceState(5, OfflineDeviceState.queued);
  });
  tearDown(() async {
    controller.dispose();
    container.dispose();
    await db.close();
    WorkmanagerPlatform.instance = previousSchedule;
  });

  void seedAttempt({
    String attempt = 'attempt-A',
    String catalog = 'catalog-A',
  }) {
    service.values[kWorkOrderKey] = jsonEncode(
      BackgroundWorkOrder(
        attemptId: attempt,
        catalogServerId: catalog,
        chapterIds: [5],
        mangaIdByChapter: {5: 1},
        serverBase: 'http://server',
        port: null,
        addPort: false,
        wifiOnly: true,
        auth: const BackgroundTokenRecord(gen: 0, authType: 'none'),
        baseDir: container.read(offlinePathsProvider).baseDir,
      ).toJson(),
    );
  }

  void refuse() {
    service.onStart = () async => ServiceRequestFailure(
      error: PlatformException(
        code: 'ForegroundServiceStartNotAllowedException',
      ),
    );
  }

  /// Pumps until [ready] holds. A bare `pumpEventQueue()` gives a fixed number
  /// of turns, so on a loaded machine an in-flight restart is asserted before
  /// it lands.
  Future<void> pumpUntil(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await pumpEventQueue(times: 1);
    }
    await pumpEventQueue();
  }

  test('server chapter errors fail only those chapters and keep downloading',
      () async {
    const message = 'SourceNotInstalledException: Source is not installed';
    final requests = <int>[];
    final events = <Map>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([1, 2, 3]);
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if ((body['query'] as String).contains('OfflineServerIdentity')) {
        request.response.write(jsonEncode({
          'data': {
            'metas': {
              'nodes': [{'value': 'catalog-A'}],
            },
          },
        }));
      } else {
        final id = body['variables']['input']['chapterId'] as int;
        requests.add(id);
        request.response.write(jsonEncode({
          'data': {
            'fetchChapterPages': id == 5
                ? {'pages': ['/ignored.jpg']}
                : id == 6
                    ? null
                    : {'pages': ['/page.jpg']},
          },
          if (id == 5) 'errors': [{'message': message}],
        }));
      }
      await request.response.close();
    });
    for (final id in [6, 7]) {
      await db.upsertChapterMetadata(
        id: id,
        mangaId: 1,
        name: 'C$id',
        chapterIndex: id,
        isRead: false,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: false,
        pageCount: 0,
        updatedAt: DateTime(2026),
      );
      await db.setChapterDeviceState(id, OfflineDeviceState.queued);
    }
    final base = 'http://127.0.0.1:${server.port}';
    await prefs.setString('offlineLastServerId', 'catalog-A');
    await prefs.setString('offlineLastServerAddress', serverAddress(
      baseUrl: base, port: null, addPort: false,
    ));
    final order = BackgroundWorkOrder(
      chapterIds: [5, 6, 7],
      mangaIdByChapter: {5: 1, 6: 1, 7: 1},
      serverBase: base,
      port: null,
      addPort: false,
      wifiOnly: false,
      auth: const BackgroundTokenRecord(gen: 0, authType: 'none'),
      baseDir: container.read(offlinePathsProvider).baseDir,
      attemptId: 'attempt-A',
      catalogServerId: 'catalog-A',
    );
    final raw = jsonEncode(order.toJson());
    service.running = true;
    service.values[kWorkOrderKey] = raw;
    controller.register();
    await controller.startupSettled;
    await FlutterForegroundTask.saveData(key: kWorkOrderKey, value: raw);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async => call.method == 'isRunningService' ? true : null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'), null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_foreground_task/methods'), null,
      );
    });
    FlutterForegroundTask.initCommunicationPort();
    void onEvent(Object data) {
      events.add(data as Map);
      service.callback!(data);
    }
    FlutterForegroundTask.addTaskDataCallback(onEvent);
    addTearDown(() async {
      FlutterForegroundTask.removeTaskDataCallback(onEvent);
      await FlutterForegroundTask.streamSubscription?.cancel();
      FlutterForegroundTask.receivePort?.close();
    });
    await HttpOverrides.runZoned(() async {
      final handler = DownloadTaskHandler();
      try {
        await handler.onStart(DateTime.now(), TaskStarter.developer)
            .timeout(const Duration(seconds: 10));
      } finally {
        await handler.onDestroy(DateTime.now(), false);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
    await pumpUntil(() => events.any((e) => e['kind'] == 'drained'));
    await pumpEventQueue();
    expect(requests, [5, 6, 7]);
    expect(events.where((e) => e['kind'] == 'parked'), isEmpty);
    final failures = events.where((e) => e['kind'] == 'chapterDone').toList();
    expect(failures.map((e) => e['status']), ['error', 'error', 'downloaded']);
    expect(failures.first['reason'], message);
    final entries = await BackgroundCompletionLog(
      File('${order.baseDir}/.bg_completion.log'),
    ).parse();
    expect(entries.whereType<ChapterEntry>().first.reason, message);
    for (final id in [5, 6]) {
      expect((await db.chapterById(id))!.deviceState, OfflineDeviceState.error);
    }
    expect((await db.chapterById(7))!.deviceState, OfflineDeviceState.downloaded);
    expect((await db.chapterById(5))!.failureReason, message);
    expect(container.read(serverUnreachableProvider), isFalse);
    expect(container.read(offlineDownloadRestrictionProvider), isNull);
    expect(notices.where((reason) => reason == 'connection'), isEmpty);
  });

  test('old same-account attempt cannot park or restart a chapter', () async {
    service.running = true;
    seedAttempt(attempt: 'attempt-B');
    controller.register();
    await controller.startupSettled;
    for (final kind in ['parked', 'chapterStart']) {
      service.callback!({
        'kind': kind,
        'chapterId': 5,
        'gen': 0,
        'total': 3,
        'catalogServerId': 'catalog-A',
        'identityEpoch': 0,
        'attemptId': 'attempt-A',
      });
    }
    await pumpEventQueue();
    expect(container.read(serverUnreachableProvider), isFalse);
    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued);
  });

  group('resume replay gating', () {
    // A queued chapter is already in the setUp, so a replay that reaches
    // ensureServiceRunning starts the FGS — service.starts is the signal.
    test('first resume at launch replays', () async {
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpUntil(() => service.starts > 0);
      expect(service.starts, greaterThan(0));
    });
  });

  test('refusal persists and automatic force does not retry', () async {
    refuse();
    await controller.ensureServiceRunning();
    await controller.ensureServiceRunning(force: true);
    await controller.requestStart();
    expect(service.starts, 1);
    expect(prefs.getString(DBKeys.offlineDownloadsStalled.name), 'background');
    expect(notices.where((n) => n == 'background'), hasLength(1));
    expect(service.values, isEmpty);
  });
}
