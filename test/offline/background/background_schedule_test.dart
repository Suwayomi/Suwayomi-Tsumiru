import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/jwt_utils.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/notifications/controller/notifications_controller.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_entry.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/background/background_schedule.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_spec_writer.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:workmanager/workmanager.dart';

import '../../helpers/offline_test_db.dart';

class _SupportDirectory extends PathProviderPlatform {
  _SupportDirectory(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Schedule extends WorkmanagerPlatform {
  final registrations = <Constraints>[];
  final cancellations = <String>[];
  bool refuseRegistration = false;

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
  }) async {
    expect(uniqueName, kNewChapterPeriodicName);
    expect(taskName, kNewChapterCheckTask);
    expect(existingWorkPolicy, ExistingPeriodicWorkPolicy.update);
    registrations.add(constraints!);
    if (refuseRegistration) throw StateError('Scheduler unavailable');
  }

  final oneOffRegistrations = <({String name, Duration? initialDelay})>[];

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
  }) async {
    oneOffRegistrations.add((name: uniqueName, initialDelay: initialDelay));
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancellations.add(uniqueName);
  }
}

class _StartAfterPublication extends BackgroundDownloadController {
  _StartAfterPublication(super.ref, this.onStart)
    : super(isAndroid: () => false, connectivityChanges: const Stream.empty());

  final Future<void> Function(bool userInitiated) onStart;

  @override
  Future<void> requestStart({bool userInitiated = false}) =>
      onStart(userInitiated);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Directory support;
  late OfflinePaths paths;
  late OfflineDatabase db;
  late ProviderContainer container;
  late _Schedule schedule;
  late PathProviderPlatform previousPaths;
  late WorkmanagerPlatform previousSchedule;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Tsumiru',
      packageName: 'io.github.aaronbamblett.tsumiru',
      version: '1.1.5',
      buildNumber: '1',
      buildSignature: '',
    );
    Workmanager();
    previousSchedule = WorkmanagerPlatform.instance;
    schedule = _Schedule();
    WorkmanagerPlatform.instance = schedule;
    previousPaths = PathProviderPlatform.instance;
    support = await Directory.systemTemp.createTemp('background-schedule-test');
    paths = OfflinePaths('${support.path}/offline');
    PathProviderPlatform.instance = _SupportDirectory(support.path);
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineCatalogServerId.name: 'catalog',
      DBKeys.offlineLastServerId.name: 'catalog',
      DBKeys.offlineLastServerAddress.name: 'https://server.test:443',
      DBKeys.serverUrl.name: 'https://server.test',
      DBKeys.serverPortToggle.name: false,
      DBKeys.notificationsNewChaptersEnabled.name: false,
      DBKeys.notificationsAppUpdatesEnabled.name: false,
      DBKeys.notificationsExtensionUpdatesEnabled.name: false,
      DBKeys.downloadOnlyOverWifi.name: false,
    });
    prefs = await SharedPreferences.getInstance();
    await CatchupStateStore(prefs).setEnabled(false);
    await CatchupStateStore(prefs).setDownloadEnabled(false);
    db = testOfflineDatabase();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineDatabaseProvider.overrideWithValue(db),
        offlinePathsProvider.overrideWithValue(paths),
        offlineEnabledProvider.overrideWith((ref) => true),
        offlineActiveProvider.overrideWith((ref) => true),
      ],
    );
    await db.upsertMangaMetadata(
      id: 1,
      title: 'Queued manga',
      updatedAt: DateTime(2026),
    );
    await db.upsertChapterMetadata(
      id: 5,
      mangaId: 1,
      name: 'Queued chapter',
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
    container.dispose();
    await db.close();
    PathProviderPlatform.instance = previousPaths;
    WorkmanagerPlatform.instance = previousSchedule;
  });

  Future<void> config({bool notices = false, bool charging = false}) =>
      NotificationStateStore(prefs).writeConfig(
        NotificationWorkerConfig(
          serverId: 'https://server.test|-',
          endpoint: const NotificationEndpoint(
            baseUrl: 'https://server.test',
            addPort: false,
          ),
          newChaptersEnabled: notices,
          includedCategoryIds: const {},
          excludedCategoryIds: const {},
          hideContent: false,
          wifiOnly: true,
          chargingOnly: charging,
          catalogServerId: 'catalog',
          verifiedAddress: 'https://server.test:443',
        ),
      );

  Future<void> complete({int generation = 0}) =>
      BackgroundCompletionLog(
        File('${paths.baseDir}/.bg_completion.log'),
      ).appendChapter(
        chapterId: 5,
        generation: generation,
        status: 'downloaded',
        pages: 2,
        bytes: 100,
      );

  String jwt(int expiry, String account) {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': account})))
        .replaceAll('=', '');
    return 'eyJhbGciOiJub25lIn0.$payload.signature';
  }

  Future<void> login(String access, String refresh) async {
    await prefs.setInt(DBKeys.authType.name, AuthType.uiLogin.index);
    await container.read(authCredentialsStoreProvider.future);
    await container
        .read(authCredentialsStoreProvider.notifier)
        .saveUiLoginTokens(accessToken: access, refreshToken: refresh);
  }

  test(
    'sync imports and preserves a worker refresh across repeated publications',
    () async {
      final oldAccess = jwt(2000000000, 'reader');
      final rotatedAccess = jwt(2000003600, 'reader');
      await login(oldAccess, 'old-refresh');
      await config();
      await NotificationStateStore(prefs).writeTokenRecord(
        BackgroundTokenRecord(
          gen: 4,
          authType: 'uiLogin',
          endpoint: 'https://server.test|-',
          accessToken: rotatedAccess,
          refreshToken: 'rotated-refresh',
        ),
      );
      await writeCatchupWorkSpec(container.read);
      await container.read(notificationsControllerProvider).sync();
      await container.read(notificationsControllerProvider).sync();

      final saved = NotificationStateStore(prefs).readTokenRecord()!;
      expect(saved.gen, 4);
      expect(saved.accessToken, rotatedAccess);
      expect(saved.refreshToken, 'rotated-refresh');
      final credentials = await container.read(
        authCredentialsStoreProvider.future,
      );
      expect(credentials.uiAccessToken, rotatedAccess);
      expect(credentials.uiRefreshToken, 'rotated-refresh');
      expect(credentials.uiAccessTokenExpiresAt, decodeJwtExp(rotatedAccess));
      expect(
        decodeJwtExp(rotatedAccess),
        DateTime.fromMillisecondsSinceEpoch(2000003600000, isUtc: true),
      );
      final secure = container.read(secureStorageProvider);
      expect(await secure.read(key: 'auth.ui.accessToken'), rotatedAccess);
      expect(await secure.read(key: 'auth.ui.refreshToken'), 'rotated-refresh');
      expect(NotificationStateStore(prefs).readConfig()!.anyEnabled, isFalse);
      expect(CatchupStateStore(prefs).enabled, isFalse);
      expect(CatchupStateStore(prefs).downloadEnabled, isFalse);
    },
  );

  test(
    'a new identity replaces the previous account worker token despite later expiry',
    () async {
      final accountAccess = jwt(2000000000, 'new-reader');
      final oldAccountAccess = jwt(2000007200, 'old-reader');
      await login(accountAccess, 'new-account-refresh');
      await config();
      await NotificationStateStore(prefs).writeTokenRecord(
        BackgroundTokenRecord(
          gen: 8,
          authType: 'uiLogin',
          endpoint: 'https://server.test|-',
          accessToken: oldAccountAccess,
          refreshToken: 'old-account-refresh',
        ),
      );
      await prefs.setInt(CatchupStateStore.identityEpochKey, 1);
      await writeCatchupWorkSpec(container.read);
      await container.read(notificationsControllerProvider).sync();

      final saved = NotificationStateStore(prefs).readTokenRecord()!;
      expect(saved.gen, 0);
      expect(saved.accessToken, accountAccess);
      expect(saved.refreshToken, 'new-account-refresh');
      final credentials = await container.read(
        authCredentialsStoreProvider.future,
      );
      expect(credentials.uiAccessToken, accountAccess);
      expect(credentials.uiRefreshToken, 'new-account-refresh');
      final savedConfig = NotificationStateStore(prefs).readConfig()!;
      expect(savedConfig.identityEpoch, 1);
      expect(savedConfig.anyEnabled, isFalse);
    },
  );

  test(
    'a scheduling failure still requests the foreground download service',
    () async {
      schedule.refuseRegistration = true;
      container.dispose();
      var starts = 0;
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(paths),
          offlineEnabledProvider.overrideWith((ref) => true),
          offlineActiveProvider.overrideWith((ref) => true),
          backgroundDownloadsPlatformProvider.overrideWithValue(true),
          credentialsProvider.overrideWithBuild((ref, notifier) async => null),
          authCredentialsStoreProvider.overrideWithBuild(
            (ref, notifier) async => const AuthCredentialsState.empty(),
          ),
          backgroundDownloadControllerProvider.overrideWith(
            (ref) => _StartAfterPublication(ref, (userInitiated) async {
              starts++;
              expect(userInitiated, isTrue);
              expect(schedule.registrations, hasLength(1));
            }),
          ),
        ],
      );
      await container.read(downloadStarterProvider)(userInitiated: true);

      expect(starts, 1);
      expect(NotificationStateStore(prefs).readConfig()!.anyEnabled, isFalse);
    },
  );

  test(
    'queued work schedules with catch-up and notifications disabled',
    () async {
      await config();
      await writeCatchupWorkSpec(container.read);
      await reconcileBackgroundSchedule();

      final spec = CatchupStateStore(prefs).readSpec()!;
      expect(spec.manga, isEmpty);
      expect(spec.queuedChapters.single.chapterId, 5);
      expect(CatchupStateStore(prefs).enabled, isFalse);
      expect(CatchupStateStore(prefs).downloadEnabled, isFalse);
      expect(NotificationStateStore(prefs).readConfig()!.anyEnabled, isFalse);
      expect(schedule.registrations.single.networkType, NetworkType.connected);
      expect(schedule.cancellations, isEmpty);
    },
  );

  test(
    'a pending server-fetch arms a short follow-up wake that stops re-arming when it clears',
    () async {
      await config();
      await writeCatchupWorkSpec(container.read);
      await CatchupStateStore(prefs).writeLedger(
        'catalog',
        const CatchupLedger(pendingServerFetch: {99: 1}),
      );
      await reconcileBackgroundSchedule();

      expect(schedule.oneOffRegistrations, hasLength(1));
      expect(schedule.oneOffRegistrations.single.name, kNewChapterFollowUpName);
      expect(
        schedule.oneOffRegistrations.single.initialDelay,
        const Duration(minutes: 15),
      );

      // The obligation clears (download landed, or the retry budget drained):
      // a one-off self-expires after one fire, so reconcile must simply stop
      // re-arming it — no new registration, and no spurious cancellation that
      // would pollute the periodic-schedule bookkeeping.
      await CatchupStateStore(
        prefs,
      ).writeLedger('catalog', const CatchupLedger());
      await reconcileBackgroundSchedule();

      expect(schedule.oneOffRegistrations, hasLength(1));
      expect(schedule.cancellations, isEmpty);

      // A pending fetch the executor has given up on is not worth a wake.
      await CatchupStateStore(prefs).writeLedger(
        'catalog',
        const CatchupLedger(
          pendingServerFetch: {99: 1},
          serverFetchRetries: {99: kMaxChapterAttempts},
        ),
      );
      await reconcileBackgroundSchedule();

      expect(schedule.oneOffRegistrations, hasLength(1));
    },
  );

  test('pausing cancels a queue-only schedule', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await reconcileBackgroundSchedule();
    await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
    await reconcileBackgroundSchedule();

    expect(schedule.registrations, hasLength(1));
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
  });

  test('completion cancels demand without foreground replay', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await complete();
    await reconcileBackgroundSchedule();

    expect((await db.chapterById(5))!.deviceState, OfflineDeviceState.queued);
    expect(schedule.registrations, isEmpty);
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
  });

  test('requeue after completion registers the new generation', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await complete();
    await reconcileBackgroundSchedule();
    await db.bumpChapterGeneration(5);
    await writeCatchupWorkSpec(container.read);
    await reconcileBackgroundSchedule();

    expect(
      CatchupStateStore(prefs).readSpec()!.queuedChapters.single.generation,
      1,
    );
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
    expect(schedule.registrations, hasLength(1));
  });

  test(
    'queue relaxes the shared job without changing notification policy',
    () async {
      await config(notices: true, charging: true);
      final original = NotificationStateStore(prefs).readConfig()!.toJson();
      await writeCatchupWorkSpec(container.read);
      await reconcileBackgroundSchedule();
      expect(schedule.registrations.last.networkType, NetworkType.connected);
      expect(schedule.registrations.last.requiresCharging, isFalse);

      await db.setChapterDeviceState(5, OfflineDeviceState.downloaded);
      await writeCatchupWorkSpec(container.read);
      await reconcileBackgroundSchedule();
      expect(schedule.registrations.last.networkType, NetworkType.unmetered);
      expect(schedule.registrations.last.requiresCharging, isTrue);
      expect(NotificationStateStore(prefs).readConfig()!.toJson(), original);
      expect(schedule.cancellations, isEmpty);
    },
  );

  test('an obsolete identity epoch cannot keep queue work scheduled', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await prefs.setInt(CatchupStateStore.identityEpochKey, 1);
    await reconcileBackgroundSchedule();

    expect(schedule.registrations, isEmpty);
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
  });

  test(
    'snapshot publications wait for schedule ownership and retain current generation',
    () async {
      final held = Completer<void>();
      final release = Completer<void>();
      final owner = withBackgroundScheduleLock(() async {
        held.complete();
        await release.future;
      }, baseDir: paths.baseDir);
      await held.future;
      var published = false;
      final first = writeCatchupWorkSpec(
        container.read,
      ).then((_) => published = true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(published, isFalse);
      expect(CatchupStateStore(prefs).readSpec(), isNull);
      await db.bumpChapterGeneration(5);
      final second = writeCatchupWorkSpec(container.read);
      release.complete();
      await Future.wait([owner, first, second]);

      expect(
        CatchupStateStore(prefs).readSpec()!.queuedChapters.single.generation,
        1,
      );
    },
  );

  test(
    'the real download starter seeds fallback before requesting a service',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Tsumiru',
        packageName: 'io.github.aaronbamblett.tsumiru',
        version: '1.1.5',
        buildNumber: '1',
        buildSignature: '',
      );
      container.dispose();
      var starts = 0;
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(paths),
          offlineEnabledProvider.overrideWith((ref) => true),
          offlineActiveProvider.overrideWith((ref) => true),
          backgroundDownloadsPlatformProvider.overrideWithValue(true),
          credentialsProvider.overrideWithBuild((ref, notifier) async => null),
          authCredentialsStoreProvider.overrideWithBuild(
            (ref, notifier) async => const AuthCredentialsState.empty(),
          ),
          backgroundDownloadControllerProvider.overrideWith(
            (ref) => _StartAfterPublication(ref, (userInitiated) async {
              starts++;
              expect(userInitiated, isTrue);
              final spec = CatchupStateStore(prefs).readSpec()!;
              expect(spec.manga, isEmpty);
              expect(spec.queuedChapters.single.chapterId, 5);
              final notifications = NotificationStateStore(prefs);
              expect(notifications.readConfig()!.anyEnabled, isFalse);
              expect(notifications.readConfig()!.catalogServerId, 'catalog');
              expect(notifications.readConfig()!.appVersion, '1.1.5');
              expect(
                notifications.readTokenRecord()!.endpoint,
                'https://server.test|-',
              );
              expect(schedule.registrations, hasLength(1));
            }),
          ),
        ],
      );
      expect(NotificationStateStore(prefs).readConfig(), isNull);
      expect(NotificationStateStore(prefs).readTokenRecord(), isNull);
      await container.read(downloadStarterProvider)(userInitiated: true);

      expect(starts, 1);
      expect(CatchupStateStore(prefs).enabled, isFalse);
      expect(CatchupStateStore(prefs).downloadEnabled, isFalse);
    },
  );
}
