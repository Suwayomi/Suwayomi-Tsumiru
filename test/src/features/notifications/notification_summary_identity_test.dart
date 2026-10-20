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
    'summary and update-error payloads retain their originating session',
    () async {
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

      // The summary and its cold-launch payload.
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
      final cold = await service.launchPayload();
      for (final payload in [summary, cold!]) {
        expect(payload.requiresSession, isTrue);
        expect(payload.mangaId, isNull);
        expect(payload.matchesConfig(configA), isTrue);
        expect(payload.matchesConfig(configB), isFalse);
      }

      // The update-error payload and its cold-launch payload.
      plugin = RecordingPlugin();
      service = LocalNotificationService(plugin);
      await service.showLibraryUpdateError(
        'Library update errors',
        'One update failed',
        identityEpoch: 4,
        catalogServerId: 'a',
        sessionFingerprint: 'session-a',
      );
      final decoded = NotificationPayload.decode(plugin.payload);
      final errorCold = await service.launchPayload();
      for (final payload in [decoded, errorCold!]) {
        expect(payload.isUpdateErrors, isTrue);
        expect(payload.requiresSession, isTrue);
        expect(payload.identityEpoch, 4);
        expect(payload.catalogServerId, 'a');
        expect(payload.sessionFingerprint, 'session-a');
        expect(payload.matchesConfig(configB), isFalse);
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
