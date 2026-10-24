// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_state_store.dart';

const kNotifActionMarkRead = 'markRead';
const kNotifActionDownload = 'download';
const kNotifActionView = 'view';

class NotificationPayload {
  const NotificationPayload.updates({
    this.identityEpoch,
    this.catalogServerId,
    this.sessionFingerprint,
    this.requiresSession = false,
  }) : mangaId = null,
       chapterId = null,
       chapterIds = const [],
       isUpdateErrors = false;

  const NotificationPayload.updateErrors({
    this.identityEpoch,
    this.catalogServerId,
    this.sessionFingerprint,
    this.requiresSession = false,
  }) : mangaId = null,
       chapterId = null,
       chapterIds = const [],
       isUpdateErrors = true;

  const NotificationPayload.chapter({
    required this.mangaId,
    required this.chapterId,
    this.chapterIds = const [],
    this.identityEpoch,
    this.catalogServerId,
    this.sessionFingerprint,
  }) : requiresSession = true,
       isUpdateErrors = false;

  final bool requiresSession;
  final int? identityEpoch;
  final String? catalogServerId;
  final String? sessionFingerprint;

  bool matchesConfig(NotificationWorkerConfig config) =>
      sessionFingerprint != null &&
      sessionFingerprint == config.sessionFingerprint &&
      identityEpoch == config.identityEpoch &&
      catalogServerId == config.catalogServerId;

  final int? mangaId;

  /// First new chapter, used as the notification tap target.
  final int? chapterId;

  /// All new chapter IDs targeted by Mark-read and Download.
  final List<int> chapterIds;

  final bool isUpdateErrors;

  String encode() => jsonEncode({
    if (requiresSession) 'kind': 'chapters',
    if (mangaId != null) 'm': mangaId,
    if (chapterId != null) 'c': chapterId,
    if (chapterIds.isNotEmpty) 'cs': chapterIds,
    if (identityEpoch != null) 'epoch': identityEpoch,
    if (catalogServerId != null) 'catalog': catalogServerId,
    if (sessionFingerprint != null) 'session': sessionFingerprint,
    if (isUpdateErrors) 'e': 1,
  });

  static NotificationPayload decode(String? raw) {
    if (raw == null || raw.isEmpty) return const NotificationPayload.updates();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      if (j['e'] == 1) {
        return NotificationPayload.updateErrors(
          requiresSession: j['kind'] != null,
          identityEpoch: j['epoch'] as int?,
          catalogServerId: j['catalog'] as String?,
          sessionFingerprint: j['session'] as String?,
        );
      }
      final m = (j['m'] as num?)?.toInt();
      if (m == null) {
        return NotificationPayload.updates(
          requiresSession: true,
          identityEpoch: j['epoch'] as int?,
          catalogServerId: j['catalog'] as String?,
          sessionFingerprint: j['session'] as String?,
        );
      }
      return NotificationPayload.chapter(
        mangaId: m,
        identityEpoch: j['epoch'] as int?,
        catalogServerId: j['catalog'] as String?,
        sessionFingerprint: j['session'] as String?,
        chapterId: (j['c'] as num?)?.toInt(),
        chapterIds: [
          for (final id in (j['cs'] as List? ?? const [])) (id as num).toInt(),
        ],
      );
    } catch (_) {
      return const NotificationPayload.updates();
    }
  }
}

/// Preformatted content usable without localization or BuildContext in any isolate.
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

  /// All new chapter IDs targeted by Mark-read and Download.
  final List<int> chapterIds;

  /// Null uses a text-only notification.
  final String? coverPath;
}

/// Notification service shared by foreground and headless isolates.
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

  // Stable IDs replace notifications on replay instead of alerting again.
  static const _summaryId = 1;
  static const _downloadsCompleteId = 2;
  static const _libraryErrorId = 3;
  static const _downloadErrorId = 4;
  static const _backupId = 5;
  static const _appUpdateId = 6;
  static const _extensionUpdateId = 7;
  static const _incognitoId = 8;
  static const _downloadStallId = 9;
  int _seriesId(int mangaId) => 100000 + (mangaId % 1000000);

  Future<void> init({
    void Function(NotificationResponse)? onTap,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundTap,
  }) async {
    const android = AndroidInitializationSettings('ic_stat_tsumiru');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );

    final android_ = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android_?.createNotificationChannel(
      const AndroidNotificationChannel(
        newChaptersChannelId,
        'New chapters',
        description: 'Notifies when followed series get new chapters',
        importance: Importance.high,
      ),
    );
    await android_?.createNotificationChannel(
      const AndroidNotificationChannel(
        downloadsChannelId,
        'Downloads',
        description: 'Notifies when downloads finish',
        importance: Importance.low,
      ),
    );
    for (final c in const [
      (libraryErrorChannelId, 'Library update errors'),
      (downloadErrorChannelId, 'Download errors'),
      (backupChannelId, 'Backup & restore'),
      (appUpdateChannelId, 'App updates'),
      (extensionUpdateChannelId, 'Extension updates'),
    ]) {
      await android_?.createNotificationChannel(
        AndroidNotificationChannel(
          c.$1,
          c.$2,
          importance: Importance.defaultImportance,
        ),
      );
    }
    await android_?.createNotificationChannel(
      const AndroidNotificationChannel(
        incognitoChannelId,
        'Incognito mode',
        description: 'Persistent reminder while incognito mode is on',
        importance: Importance.low,
      ),
    );
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  // Cap the one-tap Download action to avoid mass enqueue.
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
    int? identityEpoch,
    String? catalogServerId,
    String? sessionFingerprint,
  }) async {
    final summaryDetails = AndroidNotificationDetails(
      newChaptersChannelId,
      'New chapters',
      groupKey: _newChaptersGroup,
      setAsGroupSummary: true,
      // Only the summary alerts, so a batch produces one buzz.
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
      payload: NotificationPayload.updates(
        requiresSession: true,
        identityEpoch: identityEpoch,
        catalogServerId: catalogServerId,
        sessionFingerprint: sessionFingerprint,
      ).encode(),
    );

    if (hideContent) return;
    for (final s in series) {
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
          // Mark-read and Download run headlessly; View opens the app.
          AndroidNotificationAction(kNotifActionMarkRead, markReadLabel),
          AndroidNotificationAction(
            kNotifActionView,
            viewLabel,
            showsUserInterface: true,
          ),
          if (s.chapterIds.length <= _downloadActionMax)
            AndroidNotificationAction(
              kNotifActionDownload,
              downloadLabel,
              cancelNotification: false,
            ),
        ],
      );
      await _plugin.show(
        id: _seriesId(s.mangaId),
        title: s.title,
        body: s.body,
        notificationDetails: NotificationDetails(android: details),
        payload: NotificationPayload.chapter(
          mangaId: s.mangaId,
          identityEpoch: identityEpoch,
          catalogServerId: catalogServerId,
          sessionFingerprint: sessionFingerprint,
          chapterId: s.firstChapterId,
          chapterIds: s.chapterIds,
        ).encode(),
      );
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
      notificationDetails: const NotificationDetails(android: details),
    );
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
    bool silent = false,
  }) => _plugin.show(
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
        onlyAlertOnce: silent,
        playSound: !silent,
        enableVibration: !silent,
        autoCancel: !ongoing,
      ),
    ),
    payload: payload,
  );

  Future<void> showLibraryUpdateError(
    String title,
    String body, {
    required int identityEpoch,
    required String? catalogServerId,
    required String? sessionFingerprint,
  }) => _showSimple(
    id: _libraryErrorId,
    channelId: libraryErrorChannelId,
    channelName: 'Library update errors',
    title: title,
    body: body,
    payload: NotificationPayload.updateErrors(
      requiresSession: true,
      identityEpoch: identityEpoch,
      catalogServerId: catalogServerId,
      sessionFingerprint: sessionFingerprint,
    ).encode(),
  );

  Future<void> showDownloadError(String title, String body) => _showSimple(
    id: _downloadErrorId,
    channelId: downloadErrorChannelId,
    channelName: 'Download errors',
    title: title,
    body: body,
  );

  Future<void> showDownloadStall(
    String title,
    String body, {
    bool silent = false,
  }) => _showSimple(
    id: _downloadStallId,
    channelId: downloadErrorChannelId,
    channelName: 'Download errors',
    title: title,
    body: body,
    silent: silent,
  );

  Future<void> cancelDownloadStall() => _plugin.cancel(id: _downloadStallId);

  Future<void> showBackupResult(String title, String body) => _showSimple(
    id: _backupId,
    channelId: backupChannelId,
    channelName: 'Backup & restore',
    title: title,
    body: body,
  );

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
