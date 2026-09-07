import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/local_notification_service.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';

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
  test(
    'summary and cold-launch payloads retain their originating session',
    () async {
      final plugin = RecordingPlugin();
      final service = LocalNotificationService(plugin);
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
      final cold = await service.launchPayload();
      for (final payload in [summary, cold!]) {
        expect(payload.requiresSession, isTrue);
        expect(payload.mangaId, isNull);
        expect(
          payload.matchesConfig(
            const NotificationWorkerConfig(
              serverId: 's',
              endpoint: NotificationEndpoint(baseUrl: 'https://s'),
              newChaptersEnabled: true,
              includedCategoryIds: {},
              excludedCategoryIds: {},
              hideContent: true,
              identityEpoch: 4,
              catalogServerId: 'a',
              sessionFingerprint: 'session-a',
            ),
          ),
          isTrue,
        );
        expect(
          payload.matchesConfig(
            const NotificationWorkerConfig(
              serverId: 's',
              endpoint: NotificationEndpoint(baseUrl: 'https://s'),
              newChaptersEnabled: true,
              includedCategoryIds: {},
              excludedCategoryIds: {},
              hideContent: true,
              identityEpoch: 5,
              catalogServerId: 'b',
              sessionFingerprint: 'session-b',
            ),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'legacy chapter summaries require proof while generic notices do not',
    () {
      final legacy = NotificationPayload.decode('{}');
      expect(legacy.requiresSession, isTrue);
      expect(legacy.sessionFingerprint, isNull);
      expect(NotificationPayload.decode(null).requiresSession, isFalse);
    },
  );
}
