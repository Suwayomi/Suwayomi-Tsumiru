import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_worker.dart';
import 'package:tsumiru/src/features/notifications/data/local_notification_service.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';
import 'package:tsumiru/src/features/offline/data/background/background_schedule.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _Directories extends PathProviderPlatform {
  _Directories(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

const _endpoint = NotificationEndpoint(
  baseUrl: 'https://server',
  addPort: false,
);
BackgroundTokenRecord _token(String account) => BackgroundTokenRecord(
  gen: 0,
  authType: 'uiLogin',
  endpoint: 'https://server|-',
  identityEpoch: 0,
  catalogServerId: 'catalog',
  accessToken: account,
  refreshToken: 'refresh-$account',
  originalRefreshToken: 'refresh-$account',
  notificationSessionId: account,
);
NotificationWorkerConfig _config(String account) => NotificationWorkerConfig(
  serverId: 'https://server|-',
  endpoint: _endpoint,
  newChaptersEnabled: true,
  includedCategoryIds: {},
  excludedCategoryIds: {},
  hideContent: false,
  identityEpoch: 0,
  catalogServerId: 'catalog',
  sessionFingerprint: notificationIdentityFingerprint(_token(account)),
);

class _Client extends NotificationBackgroundClient {
  _Client(this.delayAt)
    : super(
        endpoint: _endpoint,
        record: _token('A'),
        broker: TokenBroker(
          read: () async => _token('A'),
          write: (_) async {},
          refreshFn: (_) async => (tokens: null, transient: false),
        ),
      );
  final String delayAt;
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> _delay(String stage) async {
    if (delayAt == stage) {
      started.complete();
      await release.future;
    }
  }

  @override
  Future<int> serverMaxFetchedAt() async {
    await _delay('seed');
    return 200;
  }

  @override
  Future<NewChaptersPage?> fetchNewChaptersPage({
    required String fetchedAtGte,
    String? after,
  }) async {
    await _delay('page');
    return (
      nodes: [
        (
          id: 1,
          mangaId: 1,
          chapterNumber: 1.0,
          name: 'Chapter 1',
          fetchedAt: 200,
          mangaTitle: 'A private title',
          thumbnailUrl: '/cover',
          categoryIds: <int>{},
        ),
      ],
      hasNextPage: false,
      endCursor: null,
    );
  }

  @override
  Future<List<int>?> fetchCover(String thumbnailUrl) async {
    await _delay('cover');
    return [1, 2, 3];
  }
}

class _Notifier extends LocalNotificationService {
  final titles = <String>[];
  final entered = Completer<void>();
  Completer<void>? release;
  @override
  Future<void> showNewChapters({
    required String summaryTitle,
    required String summaryText,
    required List<String> summaryLines,
    required List<SeriesNotificationContent> series,
    required bool hideContent,
    required String markReadLabel,
    required String viewLabel,
    required String downloadLabel,
    int? identityEpoch,
    String? catalogServerId,
    String? sessionFingerprint,
  }) async {
    titles.addAll(summaryLines);
    entered.complete();
    await release?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _Directories(
      (await Directory.systemTemp.createTemp('notification-owner-')).path,
    );
  });
  Future<NotificationStateStore> setupA({bool seed = false}) async {
    final store = await NotificationStateStore.open();
    await store.writeConfig(_config('A'));
    await store.writeTokenRecord(_token('A'));
    if (!seed) {
      await store.writeWatermark(
        _config('A').sessionFingerprint!,
        const NewChapterWatermark(fetchedAt: 100),
      );
    }
    return store;
  }

  Future<void> switchToB() => withBackgroundScheduleLock(() async {
    final store = await NotificationStateStore.open();
    await store.writeConfig(_config('B'));
    await store.writeTokenRecord(_token('B'));
    await store.writeWatermark(
      _config('B').sessionFingerprint!,
      const NewChapterWatermark(fetchedAt: 999),
    );
    await store.writeOutbox(
      NotificationOutbox(
        pending: [],
        nextWatermark: const NewChapterWatermark(fetchedAt: 1000),
        sessionFingerprint: _config('B').sessionFingerprint,
      ),
    );
  });
  for (final stage in ['seed', 'page', 'cover']) {
    test(
      'late A $stage cannot publish or overwrite B delivery state',
      () async {
        final store = await setupA(seed: stage == 'seed');
        final client = _Client(stage);
        final notifier = _Notifier();
        final run = runNewChapters(
          store,
          _config('A'),
          client,
          notifier,
          lookupAppLocalizations(const Locale('en')),
        );
        await client.started.future;
        await switchToB();
        client.release.complete();
        expect(await run, isTrue);
        final current = await NotificationStateStore.open();
        expect(notifier.titles, isEmpty);
        expect(
          current.readWatermark(_config('B').sessionFingerprint!).fetchedAt,
          999,
        );
        expect(current.readOutbox()!.matchesConfig(_config('B')), isTrue);
      },
    );
  }
  test(
    'account configuration waits for an admitted publication to finish',
    () async {
      final store = await setupA();
      final notifier = _Notifier()..release = Completer<void>();
      final run = runNewChapters(
        store,
        _config('A'),
        _Client('none'),
        notifier,
        lookupAppLocalizations(const Locale('en')),
      );
      await notifier.entered.future;
      var changed = false;
      final switchRun = switchToB().then((_) => changed = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(changed, isFalse);
      notifier.release!.complete();
      expect(await run, isTrue);
      await switchRun;
      final current = await NotificationStateStore.open();
      expect(notifier.titles, ['A private title']);
      expect(
        current.readWatermark(_config('B').sessionFingerprint!).fetchedAt,
        999,
      );
      expect(current.readOutbox()!.matchesConfig(_config('B')), isTrue);
    },
  );
}
