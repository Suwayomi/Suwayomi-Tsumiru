import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_worker.dart';
import 'package:tsumiru/src/features/notifications/data/local_notification_service.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BackgroundTokenRecord token(String account, String endpoint) =>
      BackgroundTokenRecord(
        gen: 0,
        authType: 'uiLogin',
        endpoint: endpoint,
        identityEpoch: 1,
        catalogServerId: 'catalog',
        originalRefreshToken: 'refresh-$account',
        notificationSessionId: 'session-$account',
        refreshToken: 'refresh-$account',
        accessToken: account,
      );
  NotificationWorkerConfig config(
    BackgroundTokenRecord record,
    NotificationEndpoint endpoint,
  ) => NotificationWorkerConfig(
    serverId: record.endpoint!,
    endpoint: endpoint,
    newChaptersEnabled: true,
    includedCategoryIds: {},
    excludedCategoryIds: {},
    hideContent: false,
    identityEpoch: record.identityEpoch!,
    catalogServerId: record.catalogServerId,
    sessionFingerprint: notificationIdentityFingerprint(record),
  );

  test('mixed config and token records never establish ownership', () {
    const endpoint = NotificationEndpoint(
      baseUrl: 'https://server',
      addPort: false,
    );
    final a = token('A', 'https://server|-');
    final b = token('B', 'https://server|-');
    final snapshot = config(a, endpoint);
    expect(snapshot.matchesToken(a), isTrue);
    expect(snapshot.matchesToken(b), isFalse);
    expect(
      snapshot.matchesToken(
        a.copyWith(accessToken: 'A2', refreshToken: 'rotated'),
      ),
      isTrue,
    );
    expect(
      NotificationWorkerConfig.fromJson(snapshot.toJson()).matchesToken(a),
      isTrue,
    );
    expect(
      NotificationWorkerConfig.fromJson({
        ...snapshot.toJson(),
        'sessionFingerprint': null,
      }).matchesToken(a),
      isFalse,
    );
  });

  test('payload proof roundtrips without credentials or endpoint', () {
    final a = token('A', 'https://private-server|-');
    final payload = NotificationPayload.chapter(
      mangaId: 1,
      chapterId: 2,
      chapterIds: [2],
      identityEpoch: 1,
      catalogServerId: 'catalog',
      sessionFingerprint: notificationIdentityFingerprint(a),
    );
    final encoded = payload.encode();
    expect(encoded, isNot(contains('refresh-A')));
    expect(encoded, isNot(contains('private-server')));
    final decoded = NotificationPayload.decode(encoded);
    expect(decoded.identityEpoch, 1);
    expect(decoded.catalogServerId, 'catalog');
    expect(decoded.sessionFingerprint, notificationIdentityFingerprint(a));
  });

  test('old and unowned actions never send with a new account token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final sent = <String?>[];
    server.listen((request) async {
      sent.add(request.headers.value('authorization'));
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': {
            'updateChapters': {'clientMutationId': null},
          },
        }),
      );
      await request.response.close();
    });
    await HttpOverrides.runZoned(() async {
      SharedPreferences.setMockInitialValues({});
      final store = await NotificationStateStore.open();
      final endpoint = NotificationEndpoint(
        baseUrl: 'http://127.0.0.1',
        port: server.port,
      );
      final address = 'http://127.0.0.1|${server.port}';
      final a = token('A', address);
      final b = token('B', address);
      final oldAction = NotificationPayload.chapter(
        mangaId: 1,
        chapterId: 2,
        chapterIds: [2],
        identityEpoch: 1,
        catalogServerId: 'catalog',
        sessionFingerprint: notificationIdentityFingerprint(a),
      );
      await store.writeConfig(config(a, endpoint));
      await store.writeTokenRecord(b);
      await handleNotificationAction(kNotifActionMarkRead, oldAction.encode());
      expect(sent, isEmpty);
      await store.writeConfig(config(b, endpoint));
      await handleNotificationAction(kNotifActionDownload, oldAction.encode());
      await handleNotificationAction(
        kNotifActionMarkRead,
        const NotificationPayload.chapter(
          mangaId: 1,
          chapterId: 2,
          chapterIds: [2],
        ).encode(),
      );
      expect(sent, isEmpty);
      final currentAction = NotificationPayload.chapter(
        mangaId: 1,
        chapterId: 2,
        chapterIds: [2],
        identityEpoch: 1,
        catalogServerId: 'catalog',
        sessionFingerprint: notificationIdentityFingerprint(b),
      );
      await handleNotificationAction(
        kNotifActionMarkRead,
        currentAction.encode(),
      );
      expect(sent, ['Bearer B']);
    }, createHttpClient: RealHttpOverrides().createHttpClient);
  });
  test('stranded outbox retains its original account proof', () {
    const endpoint = NotificationEndpoint(
      baseUrl: 'https://server',
      addPort: false,
    );
    final a = token('A', 'https://server|-');
    final b = token('B', 'https://server|-');
    final outbox = NotificationOutbox(
      pending: [],
      nextWatermark: const NewChapterWatermark(),
      sessionFingerprint: notificationIdentityFingerprint(a),
    );
    final restored = NotificationOutbox.fromJson(outbox.toJson());
    expect(restored.matchesConfig(config(a, endpoint)), isTrue);
    expect(restored.matchesConfig(config(b, endpoint)), isFalse);
    expect(
      const NotificationOutbox(
        pending: [],
        nextWatermark: NewChapterWatermark(),
      ).matchesConfig(config(a, endpoint)),
      isFalse,
    );
  });
  test('notification tags require a nonsecret session identifier', () {
    const unowned = BackgroundTokenRecord(
      gen: 0,
      authType: 'basic',
      endpoint: 'https://server|-',
      identityEpoch: 1,
      basicCredential: 'guessable-password',
    );
    expect(notificationIdentityFingerprint(unowned), isNull);
    final first = BackgroundTokenRecord.fromJson({
      ...unowned.toJson(),
      'notificationSessionId': 'random-session-one',
    });
    final second = BackgroundTokenRecord.fromJson({
      ...first.toJson(),
      'basicCredential': 'different-password',
    });
    expect(
      notificationIdentityFingerprint(first),
      notificationIdentityFingerprint(second),
    );
    final changedSession = BackgroundTokenRecord.fromJson({
      ...first.toJson(),
      'notificationSessionId': 'random-session-two',
    });
    expect(
      notificationIdentityFingerprint(first),
      isNot(notificationIdentityFingerprint(changedSession)),
    );
  });
}
