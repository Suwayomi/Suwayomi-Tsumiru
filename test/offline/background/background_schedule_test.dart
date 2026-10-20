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
import 'package:tsumiru/src/features/notifications/controller/notifications_controller.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_entry.dart';
import 'package:tsumiru/src/features/notifications/data/local_notification_service.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/background/background_schedule.dart';
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
    'notification identity survives sync but rejects a replacement login',
    () async {
      await login(jwt(2000000000, 'A'), 'refresh-A');
      final controller = container.read(notificationsControllerProvider);
      await controller.sync();
      final store = NotificationStateStore(prefs);
      final first = store.readTokenRecord()!;
      final owner = store.readConfig()!;
      final payload = NotificationPayload.chapter(
        mangaId: 1,
        chapterId: 5,
        chapterIds: [5],
        identityEpoch: owner.identityEpoch,
        catalogServerId: owner.catalogServerId,
        sessionFingerprint: owner.sessionFingerprint,
      );
      expect(controller.acceptsNotification(payload), isTrue);
      await controller.sync();
      expect(
        store.readTokenRecord()!.notificationSessionId,
        first.notificationSessionId,
      );
      await login(jwt(2000000000, 'B'), 'refresh-B');
      expect(controller.acceptsNotification(payload), isFalse);
      await controller.sync();
      expect(
        store.readTokenRecord()!.notificationSessionId,
        isNot(first.notificationSessionId),
      );
      expect(controller.acceptsNotification(payload), isFalse);
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

  test('pausing cancels a queue-only schedule', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await reconcileBackgroundSchedule();
    await prefs.setBool(DBKeys.offlineDownloadsPaused.name, true);
    await reconcileBackgroundSchedule();

    expect(schedule.registrations, hasLength(1));
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
  });

  test('an obsolete identity epoch cannot keep queue work scheduled', () async {
    await config();
    await writeCatchupWorkSpec(container.read);
    await prefs.setInt(CatchupStateStore.identityEpochKey, 1);
    await reconcileBackgroundSchedule();

    expect(schedule.registrations, isEmpty);
    expect(schedule.cancellations, [kNewChapterPeriodicName]);
  });
}
