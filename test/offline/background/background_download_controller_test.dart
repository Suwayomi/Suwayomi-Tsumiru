import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/background/download_task_handler.dart';
import 'package:tsumiru/src/features/offline/data/background/foreground_service_gateway.dart';
import 'package:tsumiru/src/features/offline/data/background/work_order_admission.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_stall.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_settings_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../helpers/offline_test_db.dart';

class FakeService extends ForegroundServiceGateway {
  DataCallback? callback;
  bool running = false;
  int starts = 0;
  Future<ServiceRequestResult> Function()? onStart;
  Future<void> Function()? onPermission;
  Future<bool> Function()? onRunning;
  final values = <String, String>{};
  final messages = <Object>[];

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
  Future<String?> read(String key) async => values[key];
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

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = testOfflineDatabase();
    final tmp = await Directory.systemTemp.createTemp('download-start-test');
    final paths = OfflinePaths(tmp.path);
    pageStore = DelayedManifestStore(paths);
    service = FakeService();
    notices = [];
    silentNotices = [];
    publishQueue = () async {};
    makeTimer = Timer.new;
    network = [ConnectivityResult.wifi];
    final controllerProvider = Provider<BackgroundDownloadController>(
      (ref) => BackgroundDownloadController(
        ref,
        gateway: service,
        isAndroid: () => true,
        identityAllowed: () => true,
        publishQueue: () => publishQueue(),
        timer: (duration, callback) => makeTimer(duration, callback),
        connectivity: () async => network,
        connectivityChanges: const Stream.empty(),
        notifyStall: (reason, {required silent}) async {
          notices.add(reason);
          silentNotices.add(silent);
        },
      ),
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineDatabaseProvider.overrideWithValue(db),
        serverInstanceIdProvider.overrideWith(
          (ref) => Completer<String>().future,
        ),
        offlinePathsProvider.overrideWithValue(paths),
        offlinePageStoreProvider.overrideWithValue(pageStore),
        offlineEnabledProvider.overrideWith((ref) => true),
        offlineActiveProvider.overrideWith((ref) => true),
      ],
    );
    controller = container.read(controllerProvider);
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
  });

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

  List<_ManualTimer> useManualTimers() {
    final timers = <_ManualTimer>[];
    makeTimer = (duration, callback) {
      final timer = _ManualTimer(duration, callback);
      timers.add(timer);
      return timer;
    };
    return timers;
  }

  void publishTimer(List<_ManualTimer> timers) {
    timers
        .singleWhere(
          (timer) =>
              timer.isActive &&
              timer.duration == const Duration(milliseconds: 250),
        )
        .fire();
  }

  test(
    'chapter metadata changes do not republish queue or repeatedly cancel a cleared stall',
    () async {
      final timers = useManualTimers();
      var publications = 0;
      publishQueue = () async {
        publications++;
      };
      controller.register();
      await pumpEventQueue();
      publishTimer(timers);
      await pumpEventQueue();
      final initial = publications;
      await db.setChapterProgress(5, lastPageRead: 1);
      await db.setChapterPageCount(5, 3);
      await pumpEventQueue();
      expect(publications, initial);
      expect(timers.where((timer) => timer.isActive), isEmpty);

      await db.setChapterDeviceState(5, OfflineDeviceState.none);
      await pumpEventQueue();
      publishTimer(timers);
      await pumpEventQueue();
      expect(publications, initial + 1);
      expect(notices.where((reason) => reason == null), hasLength(1));
      await db.setChapterProgress(5, lastPageRead: 2);
      await controller.ensureServiceRunning();
      await controller.ensureServiceRunning();
      await pumpEventQueue();
      expect(publications, initial + 1);
      expect(notices.where((reason) => reason == null), hasLength(1));
    },
  );

  for (final failFirst in [false, true]) {
    test(
      'pending queue bursts rerun after an in-flight ${failFirst ? 'failed' : 'successful'} publication',
      () async {
        final timers = useManualTimers();
        final entered = Completer<void>();
        final release = Completer<void>();
        final publishedGenerations = <int>[];
        var publications = 0;
        var active = 0;
        var maxActive = 0;
        publishQueue = () async {
          publications++;
          active++;
          if (active > maxActive) maxActive = active;
          try {
            final generation = (await db.chapterById(5))!.downloadGeneration;
            if (publications == 1) {
              entered.complete();
              await release.future;
              if (failFirst) throw StateError('Publication failed');
            }
            publishedGenerations.add(generation);
          } finally {
            active--;
          }
        };
        controller.register();
        await pumpEventQueue();
        for (var i = 0; i < 3; i++) {
          await db.bumpChapterGeneration(5);
          await pumpEventQueue();
        }
        expect(publications, 0);
        expect(timers.where((timer) => timer.isActive), hasLength(1));
        publishTimer(timers);
        await entered.future;
        for (var i = 0; i < 2; i++) {
          await db.bumpChapterGeneration(5);
          await pumpEventQueue();
          publishTimer(timers);
          await pumpEventQueue();
        }
        expect(publications, 1);
        expect(active, 1);
        release.complete();
        await pumpEventQueue();
        expect(publications, 2);
        expect(maxActive, 1);
        expect(active, 0);
        expect(publishedGenerations, failFirst ? [5] : [3, 5]);
      },
    );
  }

  test(
    'resume after refusal starts immediately without a new server backoff',
    () async {
      final timers = useManualTimers();
      refuse();
      await controller.ensureServiceRunning();
      service.onStart = null;
      await controller.replayOnResume();

      expect(service.starts, 2);
      expect(container.read(offlineDownloadsStalledProvider), isNull);
      expect(
        timers.where((timer) => timer.duration >= const Duration(seconds: 15)),
        isEmpty,
      );
    },
  );

  group('resume replay gating', () {
    // A queued chapter is already in the setUp, so a replay that reaches
    // ensureServiceRunning starts the FGS — service.starts is the signal.
    test('notification-shade peek (inactive → resumed) does not replay',
        () async {
      // Seed a non-null previous so this isn't mistaken for the launch resume.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(service.starts, 0);
    });

    test('genuine background return replays even though previous is inactive',
        () async {
      // Flutter synthesises hidden → inactive → resumed on a real return, so
      // `previous` is inactive at `resumed` just like the shade — the latch,
      // not `previous`, is what must let this through.
      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpUntil(() => service.starts > 0);
      expect(service.starts, greaterThan(0));
    });

    test('first resume at launch replays', () async {
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpUntil(() => service.starts > 0);
      expect(service.starts, greaterThan(0));
    });

    test('a second shade peek after a real return still does not replay',
        () async {
      // Real return replays and resets the latch...
      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpUntil(() => service.starts > 0);
      final afterReturn = service.starts;
      // ...so a later shade peek (inactive → resumed) must not replay again.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(service.starts, afterReturn);
    });
  });

  test('register restores a persisted stall silently', () async {
    useManualTimers();
    await container
        .read(offlineDownloadsStalledProvider.notifier)
        .set('background');
    controller.register();
    await controller.ensureServiceRunning();

    expect(service.starts, 0);
    expect(notices, ['background']);
    expect(silentNotices, [true]);
  });

  test('permits the first background start', () async {
    await controller.ensureServiceRunning();
    expect(service.starts, 1);
    expect(container.read(offlineDownloadsStalledProvider), isNull);
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

  test(
    'explicit retry grants a new attempt and clears recovered stall',
    () async {
      refuse();
      await controller.ensureServiceRunning();
      service.onStart = null;
      await controller.requestStart(userInitiated: true);
      expect(service.starts, 2);
      expect(container.read(offlineDownloadsStalledProvider), isNull);
      expect(notices.last, isNull);
    },
  );

  test('late failure retains recovery requested during startup', () async {
    final first = Completer<ServiceRequestResult>();
    service.onStart = () => first.future;
    final attempt = controller.ensureServiceRunning();
    while (service.starts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.requestStart(userInitiated: true);
    service.onStart = null;
    first.complete(
      ServiceRequestFailure(
        error: PlatformException(
          code: 'ForegroundServiceStartNotAllowedException',
        ),
      ),
    );
    await attempt;
    expect(service.starts, 2);
    expect(container.read(offlineDownloadsStalledProvider), isNull);
  });

  test('generic failure has a service reason', () async {
    service.onStart = () async =>
        ServiceRequestFailure(error: StateError('start'));
    await controller.ensureServiceRunning();
    expect(container.read(offlineDownloadsStalledProvider), 'service');
  });

  test('running service receives work despite a persisted refusal', () async {
    refuse();
    await controller.ensureServiceRunning();
    service.running = true;
    await controller.ensureServiceRunning();
    expect(service.starts, 1);
    expect(service.messages, isNotEmpty);
  });
  for (final queueState in ['queued', 'paused', 'empty']) {
    test(
      'Wi-Fi policy publishes with an unchanged $queueState queue',
      () async {
        if (queueState == 'paused') {
          await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
        } else if (queueState == 'empty') {
          await db.setChapterDeviceState(5, OfflineDeviceState.none);
        }
        final before = await db.chapterById(5);
        var publications = 0;
        publishQueue = () async {
          publications++;
        };

        await controller.onWifiOnlyChanged(false);
        expect(publications, 1);
        await controller.onWifiOnlyChanged(true);
        expect(publications, 2);
        expect(await db.chapterById(5), before);
      },
    );
  }

  test(
    'failed Wi-Fi policy publication still stops metered downloads',
    () async {
      service.running = true;
      network = [ConnectivityResult.mobile];
      var publications = 0;
      publishQueue = () async {
        publications++;
        expect(service.running, isTrue);
        expect(service.messages, isEmpty);
        throw StateError('Policy publication failed');
      };

      await controller.onWifiOnlyChanged(true);

      expect(publications, 1);
      expect(service.messages, [
        {'op': 'setWifiOnly', 'value': true},
      ]);
      expect(service.running, isFalse);
      expect(notices.last, 'wifi');
    },
  );

  for (final state in ['queued', 'paused', 'refused']) {
    test('relaxing Wi-Fi policy respects $state download admission', () async {
      useManualTimers();
      if (state == 'refused') {
        refuse();
        await controller.ensureServiceRunning();
        expect(service.starts, 1);
        service.onStart = null;
      } else if (state == 'paused') {
        await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
      }
      network = [ConnectivityResult.mobile];
      await prefs.setBool(DBKeys.downloadOnlyOverWifi.name, true);
      controller.register();
      await pumpEventQueue();
      await controller.ensureServiceRunning();
      expect(service.running, isFalse);
      final startsBeforeChange = service.starts;

      final expectedStarts =
          startsBeforeChange + (state == 'queued' ? 1 : 0);
      container.read(offlineWifiOnlyProvider.notifier).update(false);
      await pumpUntil(() => service.starts >= expectedStarts);

      expect(service.starts, expectedStarts);
      expect(service.running, state == 'queued');
      if (state == 'refused') {
        expect(container.read(offlineDownloadsStalledProvider), 'background');
      }
    });
  }

  test('connection restriction masks refusal without releasing it', () async {
    refuse();
    await controller.ensureServiceRunning();
    network = [ConnectivityResult.none];
    await controller.ensureServiceRunning();
    expect(notices.last, 'connection');
    network = [ConnectivityResult.mobile];
    await controller.ensureServiceRunning();
    expect(notices.last, 'wifi');
    network = [ConnectivityResult.wifi];
    await controller.ensureServiceRunning(force: true);
    expect(notices.last, 'background');
    expect(service.starts, 1);
  });

  test(
    'pause during permission setup clears the published work order',
    () async {
      service.onPermission = () async {
        await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
      };
      await controller.ensureServiceRunning();
      expect(service.starts, 0);
      expect(service.values, isEmpty);
      expect(container.read(offlineDownloadsStalledProvider), isNull);
    },
  );

  test(
    'handoff waits through delayed native shutdown before restarting',
    () async {
      final timers = useManualTimers();
      service.running = true;
      await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
      await controller.pause();
      await prefs.setBool(DBKeys.offlineDownloadsPaused.name, false);
      await controller.resume();

      for (var i = 0; i < 3; i++) {
        timers.singleWhere((timer) => timer.isActive).fire();
        await pumpEventQueue();
        expect(service.starts, 0);
        expect(service.messages, [
          {'op': 'pause'},
        ]);
        expect(
          timers.singleWhere((timer) => timer.isActive).duration,
          const Duration(milliseconds: 500),
        );
      }

      service.running = false;
      timers.singleWhere((timer) => timer.isActive).fire();
      await pumpUntil(() => service.starts >= 1);

      expect(service.starts, 1);
      expect(service.running, isTrue);
      expect(service.messages, [
        {'op': 'pause'},
      ]);
    },
  );

  test(
    'control during handoff permission wait does not park the restart',
    () async {
      final timers = useManualTimers();
      final permissionEntered = Completer<void>();
      final permissionRelease = Completer<void>();
      service.onPermission = () async {
        permissionEntered.complete();
        await permissionRelease.future;
      };
      await controller.withOwnership(() async {});
      timers.singleWhere((timer) => timer.isActive).fire();
      await permissionEntered.future;

      final controlEntered = Completer<void>();
      final controlRelease = Completer<void>();
      final control = controller.withOwnership(() async {
        controlEntered.complete();
        await controlRelease.future;
      });
      await controlEntered.future;
      permissionRelease.complete();
      await pumpEventQueue();

      expect(service.starts, 0);
      expect(service.values, isEmpty);
      expect(
        timers.where((timer) => timer.duration == const Duration(seconds: 15)),
        isEmpty,
      );

      service.onPermission = null;
      controlRelease.complete();
      await control;
      expect(
        timers.singleWhere((timer) => timer.isActive).duration,
        const Duration(milliseconds: 500),
      );
      timers.singleWhere((timer) => timer.isActive).fire();
      await pumpUntil(() => service.starts >= 1);

      expect(service.starts, 1);
      expect(service.running, isTrue);
    },
  );

  test('handoff survives a pending native start response', () async {
    final timers = useManualTimers();
    final startEntered = Completer<void>();
    final startRelease = Completer<ServiceRequestResult>();
    service.onStart = () {
      startEntered.complete();
      return startRelease.future;
    };
    final starting = controller.ensureServiceRunning();
    await startEntered.future;
    service.running = true;
    await controller.pause();

    timers.singleWhere((timer) => timer.isActive).fire();
    await pumpUntil(() => service.starts >= 1);
    expect(service.starts, 1);
    expect(service.messages, [
      {'op': 'pause'},
    ]);
    expect(
      timers.singleWhere((timer) => timer.isActive).duration,
      const Duration(milliseconds: 500),
    );

    startRelease.complete(const ServiceRequestSuccess());
    await starting;
    service.onStart = null;
    service.running = false;
    timers.singleWhere((timer) => timer.isActive).fire();
    await pumpUntil(() => service.starts >= 2);

    expect(service.starts, 2);
    expect(service.running, isTrue);
    expect(service.messages, [
      {'op': 'pause'},
    ]);
  });

  test('forced handoff survives control during native running query', () async {
    final timers = useManualTimers();
    controller.register();
    await pumpEventQueue();
    service.callback!({'kind': 'parked', 'chapterId': 5, 'mangaId': 1});
    await pumpEventQueue();
    final parkTimer = timers.singleWhere(
      (timer) =>
          timer.isActive && timer.duration == const Duration(seconds: 15),
    );
    await controller.withOwnership(() async {
      await controller.requestStart(userInitiated: true);
    });

    final runningEntered = Completer<void>();
    final runningRelease = Completer<bool>();
    service.onRunning = () {
      runningEntered.complete();
      return runningRelease.future;
    };
    timers
        .singleWhere(
          (timer) =>
              timer.isActive &&
              timer.duration == const Duration(milliseconds: 500),
        )
        .fire();
    await runningEntered.future;
    final controlEntered = Completer<void>();
    final controlRelease = Completer<void>();
    final control = controller.withOwnership(() async {
      controlEntered.complete();
      await controlRelease.future;
    });
    await controlEntered.future;
    runningRelease.complete(false);
    await pumpEventQueue();
    expect(service.starts, 0);
    expect(parkTimer.isActive, isTrue);

    service.onRunning = null;
    controlRelease.complete();
    await control;
    timers
        .singleWhere(
          (timer) =>
              timer.isActive &&
              timer.duration == const Duration(milliseconds: 500),
        )
        .fire();
    await pumpUntil(() => service.starts >= 1);

    expect(service.starts, 1);
    expect(parkTimer.isActive, isFalse);
  });

  test('cold launch releases a persisted refusal', () async {
    await container
        .read(offlineDownloadsStalledProvider.notifier)
        .set('background');
    await controller.ensureServiceRunning();
    expect(service.starts, 0);
    await controller.maybeStartAfterReplay();
    expect(service.starts, 1);
  });

  test(
    'deleting the last queued chapter clears stall without starting',
    () async {
      controller.register();
      refuse();
      await controller.ensureServiceRunning();
      await db.setChapterDeviceState(5, OfflineDeviceState.none);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(offlineDownloadsStalledProvider), isNull);
      expect(notices.last, isNull);
      expect(service.starts, 1);
    },
  );

  test(
    'a native worker that claimed the attempt keeps its credentials',
    () async {
      service.onStart = () async {
        final order = jsonDecode(service.values[kWorkOrderKey]!) as Map;
        service.values[kAcceptedWorkOrderKey] = order['attemptId'] as String;
        return ServiceRequestFailure(error: StateError('late response'));
      };
      await controller.ensureServiceRunning();
      expect(service.values[kWorkOrderKey], isNotNull);
      expect(service.values[kTokenRecordKey], isNotNull);
    },
  );

  test('cancelled chapter is removed from the durable restart order', () async {
    await controller.ensureServiceRunning();
    await controller.onRemoved(5);
    final order = jsonDecode(service.values[kWorkOrderKey]!) as Map;
    expect(order['chapterIds'], isEmpty);
  });

  test(
    'late start failure cannot overwrite confirmed live ownership',
    () async {
      service.onStart = () async {
        final order = jsonDecode(service.values[kWorkOrderKey]!) as Map;
        service.values[kAcceptedWorkOrderKey] = order['attemptId'] as String;
        service.running = true;
        return ServiceRequestFailure(error: StateError('already started'));
      };
      await controller.ensureServiceRunning();
      expect(container.read(offlineDownloadsStalledProvider), isNull);
      expect(notices.whereType<String>(), isEmpty);
    },
  );
  test(
    'removal during permission setup cannot publish the old queue',
    () async {
      service.onPermission = () async {
        await db.setChapterDeviceState(5, OfflineDeviceState.none);
        await controller.onRemoved(5);
      };
      await controller.ensureServiceRunning();
      expect(service.starts, 0);
      expect(service.values, isEmpty);
    },
  );

  test(
    'pause during a failing start cannot restore the stall or token',
    () async {
      final pending = Completer<ServiceRequestResult>();
      service.onStart = () => pending.future;
      final start = controller.ensureServiceRunning();
      while (service.starts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
      await controller.pause();
      pending.complete(ServiceRequestFailure(error: StateError('refused')));
      await start;
      expect(container.read(offlineDownloadsStalledProvider), isNull);
      expect(service.values, isEmpty);
      expect(notices.last, isNull);
    },
  );
  test(
    'removal waits for an already dispatched completion before acknowledgement',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      pageStore.onManifest = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return null;
      };
      service.running = true;
      controller.register();
      service.callback!({
        'kind': 'chapterDone',
        'chapterId': 5,
        'status': 'downloaded',
        'gen': 0,
      });
      await entered.future;
      var removed = false;
      final removal = controller.withOwnership(() async {
        await db.bumpChapterGeneration(5);
        await db.setChapterDeviceState(5, OfflineDeviceState.none);
        removed = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(removed, isFalse);
      release.complete();
      await removal;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.none);
      expect((await db.chapterById(5))!.downloadGeneration, 1);
    },
  );

  test('exhausted Android budget has its own persisted reason', () async {
    service.onStart = () async => ServiceRequestFailure(
      error: PlatformException(
        code: 'ForegroundServiceStartNotAllowedException',
        message:
            'Time limit already exhausted for foreground service type dataSync',
      ),
    );
    await controller.ensureServiceRunning();
    expect(container.read(offlineDownloadsStalledProvider), 'budget');
    await controller.ensureServiceRunning(force: true);
    expect(service.starts, 1);
  });
}
