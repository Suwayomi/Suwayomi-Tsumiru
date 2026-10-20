import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/local_notification_service.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

class RecordingPlugin implements FlutterLocalNotificationsPlugin {
  String? payload;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #show) {
      payload = invocation.namedArguments[#payload] as String?;
      return Future<void>.value();
    }
    if (invocation.memberName == #getNotificationAppLaunchDetails) {
      return Future<NotificationAppLaunchDetails?>.value(
        NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: payload,
          ),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BackgroundTokenRecord token(
    String account,
    String endpoint, {
    String? catalog = 'catalog',
  }) => BackgroundTokenRecord(
    gen: 0,
    authType: 'uiLogin',
    endpoint: endpoint,
    identityEpoch: 1,
    catalogServerId: catalog,
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

  test('ownership proof covers config, payload, outbox and session tags', () async {
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

    // Payload proof round-trips without credentials or endpoint.
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

    // A stranded outbox retains its original account proof.
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

    // Notification tags require a nonsecret session identifier.
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

    // Summary and update-error payloads retain their originating session.
    const configA = NotificationWorkerConfig(
      serverId: 's',
      endpoint: NotificationEndpoint(baseUrl: 'https://s'),
      newChaptersEnabled: true,
      includedCategoryIds: {},
      excludedCategoryIds: {},
      hideContent: true,
      identityEpoch: 4,
      catalogServerId: 'a',
      sessionFingerprint: 'session-a',
    );
    const configB = NotificationWorkerConfig(
      serverId: 's',
      endpoint: NotificationEndpoint(baseUrl: 'https://s'),
      newChaptersEnabled: true,
      includedCategoryIds: {},
      excludedCategoryIds: {},
      hideContent: true,
      identityEpoch: 5,
      catalogServerId: 'b',
      sessionFingerprint: 'session-b',
    );
    var plugin = RecordingPlugin();
    var service = LocalNotificationService(plugin);
    await service.showNewChapters(
      summaryTitle: 'New',
      summaryText: 'Chapters',
      summaryLines: [],
      series: [],
      hideContent: true,
      markReadLabel: 'Read',
      viewLabel: 'View',
      downloadLabel: 'Download',
      identityEpoch: 4,
      catalogServerId: 'a',
      sessionFingerprint: 'session-a',
    );
    final summary = NotificationPayload.decode(plugin.payload);
    for (final item in [summary]) {
      expect(item.requiresSession, isTrue);
      expect(item.mangaId, isNull);
      expect(item.matchesConfig(configA), isTrue);
      expect(item.matchesConfig(configB), isFalse);
    }
    plugin = RecordingPlugin();
    service = LocalNotificationService(plugin);
    await service.showLibraryUpdateError(
      'Library update errors',
      'One update failed',
      identityEpoch: 4,
      catalogServerId: 'a',
      sessionFingerprint: 'session-a',
    );
    final decodedError = NotificationPayload.decode(plugin.payload);
    expect(decodedError.isUpdateErrors, isTrue);
    expect(decodedError.requiresSession, isTrue);
    expect(decodedError.identityEpoch, 4);
    expect(decodedError.catalogServerId, 'a');
    expect(decodedError.sessionFingerprint, 'session-a');
    expect(decodedError.matchesConfig(configB), isFalse);
  });
}
