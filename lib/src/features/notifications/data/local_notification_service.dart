// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Action ids on a per-series notification (Komikku parity).
const kNotifActionMarkRead = 'markRead';
const kNotifActionDownload = 'download';
const kNotifActionView = 'view';

/// Payload carried by a notification tap/action, so the (foreground or
/// headless) handler can route/act without any object graph.
class NotificationPayload {
  const NotificationPayload.updates()
      : mangaId = null,
        chapterId = null,
        chapterIds = const [];
  const NotificationPayload.chapter({
    required this.mangaId,
    required this.chapterId,
    this.chapterIds = const [],
  });

  final int? mangaId;

  /// The first new chapter — the tap target.
  final int? chapterId;

  /// Every new chapter in this series' notification — the Mark-read / Download
  /// action targets.
  final List<int> chapterIds;

  String encode() => jsonEncode({
        if (mangaId != null) 'm': mangaId,
        if (chapterId != null) 'c': chapterId,
        if (chapterIds.isNotEmpty) 'cs': chapterIds,
      });

  static NotificationPayload decode(String? raw) {
    if (raw == null || raw.isEmpty) return const NotificationPayload.updates();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final m = (j['m'] as num?)?.toInt();
      if (m == null) return const NotificationPayload.updates();
      return NotificationPayload.chapter(
        mangaId: m,
        chapterId: (j['c'] as num?)?.toInt(),
        chapterIds: [
          for (final id in (j['cs'] as List? ?? const [])) (id as num).toInt()
        ],
      );
    } catch (_) {
      return const NotificationPayload.updates();
    }
  }
}

/// One series' rendered notification content (formatted by the worker, so this
/// service stays free of localization/BuildContext and works in any isolate).
class SeriesNotificationContent {
  const SeriesNotificationContent({
    required this.mangaId,
    required this.title,
    required this.body,
    required this.firstChapterId,
    required this.chapterIds,
    this.coverPath,
  });
  final int mangaId;
  final String title;
  final String body;
  final int firstChapterId;

  /// Every new chapter id — the Mark-read / Download action targets.
  final List<int> chapterIds;

  /// Local file path of the fetched cover, or null → text-only fallback.
  final String? coverPath;
}

/// Thin wrapper over `flutter_local_notifications`: channels, a grouped summary
/// + per-series children (Mihon/Komikku shape), and download-complete. Usable
/// from the UI isolate and the headless worker isolate alike.
class LocalNotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const newChaptersChannelId = 'new_chapters';
  static const downloadsChannelId = 'downloads_complete';
  static const libraryErrorChannelId = 'library_errors';
  static const downloadErrorChannelId = 'download_errors';
  static const backupChannelId = 'backup_restore';
  static const appUpdateChannelId = 'app_update';
  static const extensionUpdateChannelId = 'extension_update';
  static const incognitoChannelId = 'incognito';
  static const _newChaptersGroup = 'com.tsumiru.NEW_CHAPTERS';

  // Stable ids: one summary, per-series keyed on manga id (kept in a band well
  // clear of the summary), so a re-publish REPLACES rather than re-buzzes.
  static const _summaryId = 1;
  static const _downloadsCompleteId = 2;
  static const _libraryErrorId = 3;
  static const _downloadErrorId = 4;
  static const _backupId = 5;
  static const _appUpdateId = 6;
  static const _extensionUpdateId = 7;
  static const _incognitoId = 8;
  int _seriesId(int mangaId) => 100000 + (mangaId % 1000000);

  Future<void> init({
    void Function(NotificationResponse)? onTap,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundTap,
  }) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );

    final android_ = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      newChaptersChannelId,
      'New chapters',
      description: 'Notifies when followed series get new chapters',
      importance: Importance.high,
    ));
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      downloadsChannelId,
      'Downloads',
      description: 'Notifies when downloads finish',
      importance: Importance.low,
    ));
    for (final c in const [
      (libraryErrorChannelId, 'Library update errors'),
      (downloadErrorChannelId, 'Download errors'),
      (backupChannelId, 'Backup & restore'),
      (appUpdateChannelId, 'App updates'),
      (extensionUpdateChannelId, 'Extension updates'),
    ]) {
      await android_?.createNotificationChannel(
        AndroidNotificationChannel(c.$1, c.$2, importance: Importance.defaultImportance),
      );
    }
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      incognitoChannelId,
      'Incognito mode',
      description: 'Persistent reminder while incognito mode is on',
      importance: Importance.low,
    ));
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Posts the grouped summary + one notification per series. [summaryTitle]
  /// and [summaryLines] are pre-localized; [hideContent] suppresses the
  /// per-series children and the title list (privacy).
  /// Komikku only offers the one-tap Download action when the new-chapter count
  /// is at/below its queue-warning threshold, to avoid a mass enqueue.
  static const _downloadActionMax = 10;

  Future<void> showNewChapters({
    required String summaryTitle,
    required String summaryText,
    required List<String> summaryLines,
    required List<SeriesNotificationContent> series,
    required bool hideContent,
    required String markReadLabel,
    required String viewLabel,
    required String downloadLabel,
  }) async {
    final summaryDetails = AndroidNotificationDetails(
      newChaptersChannelId,
      'New chapters',
      groupKey: _newChaptersGroup,
      setAsGroupSummary: true,
      // Only the summary alerts — children stay silent, so N new series is one
      // buzz, not N (Komikku `setGroupAlertBehavior(GROUP_ALERT_SUMMARY)`).
      groupAlertBehavior: GroupAlertBehavior.summary,
      onlyAlertOnce: true,
      autoCancel: true,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: hideContent
          ? null
          : InboxStyleInformation(summaryLines, contentTitle: summaryTitle),
    );
    await _plugin.show(
        id: _summaryId,
        title: summaryTitle,
        body: summaryText,
        notificationDetails: NotificationDetails(android: summaryDetails),
        payload: const NotificationPayload.updates().encode());

    if (hideContent) return;
    for (final s in series) {
      // Komikku shows the cover via BigPicture (LibraryUpdateNotifier.kt:249);
      // fall back to big-text when the cover fetch failed.
      final cover = s.coverPath;
      final StyleInformation style = cover != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(cover),
              largeIcon: FilePathAndroidBitmap(cover),
              contentTitle: s.title,
              summaryText: s.body,
            )
          : BigTextStyleInformation(s.body, contentTitle: s.title);
      final details = AndroidNotificationDetails(
        newChaptersChannelId,
        'New chapters',
        groupKey: _newChaptersGroup,
        groupAlertBehavior: GroupAlertBehavior.summary,
        onlyAlertOnce: true,
        autoCancel: true,
        importance: Importance.high,
        priority: Priority.high,
        largeIcon: cover != null ? FilePathAndroidBitmap(cover) : null,
        styleInformation: style,
        actions: [
          // Mark-read / Download act headlessly (no UI); View opens the app.
          AndroidNotificationAction(kNotifActionMarkRead, markReadLabel),
          AndroidNotificationAction(kNotifActionView, viewLabel,
              showsUserInterface: true),
          if (s.chapterIds.length <= _downloadActionMax)
            AndroidNotificationAction(kNotifActionDownload, downloadLabel,
                cancelNotification: false),
        ],
      );
      await _plugin.show(
          id: _seriesId(s.mangaId),
          title: s.title,
          body: s.body,
          notificationDetails: NotificationDetails(android: details),
          payload: NotificationPayload.chapter(
            mangaId: s.mangaId,
            chapterId: s.firstChapterId,
            chapterIds: s.chapterIds,
          ).encode());
    }
  }

  Future<void> showDownloadsComplete({
    required String title,
    required String body,
  }) async {
    const details = AndroidNotificationDetails(
      downloadsChannelId,
      'Downloads',
      importance: Importance.low,
      priority: Priority.low,
      autoCancel: true,
    );
    await _plugin.show(
        id: _downloadsCompleteId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: details));
  }

  Future<void> _showSimple({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    String? payload,
    Importance importance = Importance.defaultImportance,
    bool ongoing = false,
  }) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: importance,
            priority: importance == Importance.high
                ? Priority.high
                : Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body, contentTitle: title),
            ongoing: ongoing,
            autoCancel: !ongoing,
          ),
        ),
        payload: payload,
      );

  Future<void> showLibraryUpdateError(String title, String body) => _showSimple(
        id: _libraryErrorId,
        channelId: libraryErrorChannelId,
        channelName: 'Library update errors',
        title: title,
        body: body,
      );

  Future<void> showDownloadError(String title, String body) => _showSimple(
        id: _downloadErrorId,
        channelId: downloadErrorChannelId,
        channelName: 'Download errors',
        title: title,
        body: body,
      );

  Future<void> showBackupResult(String title, String body) => _showSimple(
        id: _backupId,
        channelId: backupChannelId,
        channelName: 'Backup & restore',
        title: title,
        body: body,
      );

  /// Tapping opens the release page (payload = a URL the launch handler routes).
  Future<void> showAppUpdate(String title, String body, String? url) =>
      _showSimple(
        id: _appUpdateId,
        channelId: appUpdateChannelId,
        channelName: 'App updates',
        title: title,
        body: body,
        payload: url == null ? null : 'url:$url',
        importance: Importance.high,
      );

  Future<void> showExtensionUpdates(String title, String body) => _showSimple(
        id: _extensionUpdateId,
        channelId: extensionUpdateChannelId,
        channelName: 'Extension updates',
        title: title,
        body: body,
      );

  /// Persistent, non-dismissible while incognito mode is on (Komikku parity).
  Future<void> showIncognito(String title, String body) => _showSimple(
        id: _incognitoId,
        channelId: incognitoChannelId,
        channelName: 'Incognito mode',
        title: title,
        body: body,
        importance: Importance.low,
        ongoing: true,
      );

  Future<void> cancelIncognito() => _plugin.cancel(id: _incognitoId);

  Future<NotificationPayload?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return NotificationPayload.decode(details?.notificationResponse?.payload);
  }
}
