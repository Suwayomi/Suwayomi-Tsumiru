// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../constants/app_distribution.dart';
import '../../offline/data/background/background_token_record.dart';
import '../domain/new_chapter_detection.dart';
import 'background/notification_background_client.dart';

String? notificationIdentityFingerprint(BackgroundTokenRecord record) {
  if (record.endpoint == null ||
      record.endpoint!.isEmpty ||
      record.identityEpoch == null) {
    return null;
  }
  final sessionId = record.notificationSessionId;
  if (sessionId == null || sessionId.isEmpty) return null;
  return const Uuid().v5(
    Namespace.url.value,
    jsonEncode([
      'tsumiru/notification-session/v1',
      record.authType,
      record.endpoint,
      record.identityEpoch,
      record.catalogServerId,
      sessionId,
    ]),
  );
}

/// Foreground-written worker config; serverId scopes detection state across server switches.
class NotificationWorkerConfig {
  const NotificationWorkerConfig({
    required this.serverId,
    required this.endpoint,
    required this.newChaptersEnabled,
    required this.includedCategoryIds,
    required this.excludedCategoryIds,
    required this.hideContent,
    bool appUpdatesEnabled = false,
    this.extensionUpdatesEnabled = false,
    this.appVersion = '',
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.intervalHours = 6,
    this.catalogServerId,
    this.identityEpoch = 0,
    this.verifiedAddress,
    this.sessionFingerprint,
  }) : _appUpdatesEnabled = appUpdatesEnabled;

  final String serverId;
  final NotificationEndpoint endpoint;
  final bool newChaptersEnabled;
  final bool _appUpdatesEnabled;
  bool get appUpdatesEnabled => !isGooglePlayBuild && _appUpdatesEnabled;
  final bool extensionUpdatesEnabled;
  final bool wifiOnly;
  final bool chargingOnly;
  final int intervalHours;
  final String? catalogServerId;
  final int identityEpoch;
  final String? verifiedAddress;
  final String? sessionFingerprint;

  bool matchesToken(BackgroundTokenRecord record) =>
      sessionFingerprint != null &&
      sessionFingerprint == notificationIdentityFingerprint(record) &&
      serverId == record.endpoint &&
      serverId ==
          '${endpoint.baseUrl}|${endpoint.addPort ? endpoint.port ?? "-" : "-"}' &&
      identityEpoch == record.identityEpoch &&
      catalogServerId == record.catalogServerId;

  /// Persist the version so the worker needs no plugin call in its isolate.
  final String appVersion;

  bool get anyEnabled =>
      newChaptersEnabled || appUpdatesEnabled || extensionUpdatesEnabled;

  /// Empty include allows all categories; exclusion takes precedence.
  final Set<int> includedCategoryIds;
  final Set<int> excludedCategoryIds;
  final bool hideContent;

  Map<String, Object?> toJson() => {
    'serverId': serverId,
    'endpoint': endpoint.toJson(),
    'newChaptersEnabled': newChaptersEnabled,
    'includedCategoryIds': includedCategoryIds.toList(),
    'excludedCategoryIds': excludedCategoryIds.toList(),
    'hideContent': hideContent,
    'appUpdatesEnabled': appUpdatesEnabled,
    'extensionUpdatesEnabled': extensionUpdatesEnabled,
    'appVersion': appVersion,
    'wifiOnly': wifiOnly,
    'chargingOnly': chargingOnly,
    'intervalHours': intervalHours,
    'catalogServerId': catalogServerId,
    'identityEpoch': identityEpoch,
    'verifiedAddress': verifiedAddress,
    'sessionFingerprint': sessionFingerprint,
  };

  factory NotificationWorkerConfig.fromJson(Map<String, Object?> j) =>
      NotificationWorkerConfig(
        serverId: j['serverId'] as String,
        endpoint: NotificationEndpoint.fromJson(
          (j['endpoint'] as Map).cast<String, Object?>(),
        ),
        newChaptersEnabled: (j['newChaptersEnabled'] as bool?) ?? false,
        appUpdatesEnabled: (j['appUpdatesEnabled'] as bool?) ?? false,
        extensionUpdatesEnabled:
            (j['extensionUpdatesEnabled'] as bool?) ?? false,
        appVersion: (j['appVersion'] as String?) ?? '',
        wifiOnly: (j['wifiOnly'] as bool?) ?? true,
        chargingOnly: (j['chargingOnly'] as bool?) ?? false,
        intervalHours: (j['intervalHours'] as num?)?.toInt() ?? 6,
        catalogServerId: j['catalogServerId'] as String?,
        identityEpoch: (j['identityEpoch'] as num?)?.toInt() ?? 0,
        verifiedAddress: j['verifiedAddress'] as String?,
        sessionFingerprint: j['sessionFingerprint'] as String?,
        includedCategoryIds: {
          for (final id in (j['includedCategoryIds'] as List? ?? const []))
            (id as num).toInt(),
        },
        excludedCategoryIds: {
          for (final id in (j['excludedCategoryIds'] as List? ?? const []))
            (id as num).toInt(),
        },
        hideContent: (j['hideContent'] as bool?) ?? false,
      );

  /// Resolves category scope from live membership; null permits all manga.
  Set<int>? allowedMangaIds(Map<int, Set<int>> mangaCategoryIds) {
    if (includedCategoryIds.isEmpty && excludedCategoryIds.isEmpty) return null;
    return {
      for (final entry in mangaCategoryIds.entries)
        if (_categoryAllowed(entry.value)) entry.key,
    };
  }

  bool _categoryAllowed(Set<int> mangaCats) {
    if (excludedCategoryIds.isNotEmpty &&
        mangaCats.any(excludedCategoryIds.contains)) {
      return false;
    }
    if (includedCategoryIds.isEmpty) return true;
    return mangaCats.any(includedCategoryIds.contains);
  }
}

/// Durable notification content that can replay without another network request.
class PendingSeriesNotification {
  const PendingSeriesNotification({
    required this.mangaId,
    required this.mangaTitle,
    required this.thumbnailUrl,
    required this.chapterIds,
    required this.chapterNumbers,
    required this.firstChapterId,
    required this.totalCount,
  });

  final int mangaId;
  final String mangaTitle;
  final String? thumbnailUrl;
  final List<int> chapterIds;
  final List<double> chapterNumbers;

  /// Earliest new chapter by number, used as the tap target.
  final int firstChapterId;
  final int totalCount;

  Map<String, Object?> toJson() => {
    'mangaId': mangaId,
    'mangaTitle': mangaTitle,
    'thumbnailUrl': thumbnailUrl,
    'chapterIds': chapterIds,
    'chapterNumbers': chapterNumbers,
    'firstChapterId': firstChapterId,
    'totalCount': totalCount,
  };

  factory PendingSeriesNotification.fromJson(Map<String, Object?> j) =>
      PendingSeriesNotification(
        mangaId: (j['mangaId'] as num).toInt(),
        mangaTitle: j['mangaTitle'] as String,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        chapterIds: [
          for (final id in (j['chapterIds'] as List)) (id as num).toInt(),
        ],
        chapterNumbers: [
          for (final n in (j['chapterNumbers'] as List)) (n as num).toDouble(),
        ],
        firstChapterId: (j['firstChapterId'] as num).toInt(),
        totalCount: (j['totalCount'] as num).toInt(),
      );
}

/// Persist batch and next cursor atomically before publishing; stable IDs make crash replay safe.
class NotificationOutbox {
  const NotificationOutbox({
    required this.pending,
    required this.nextWatermark,
    this.sessionFingerprint,
  });
  final List<PendingSeriesNotification> pending;
  final NewChapterWatermark nextWatermark;
  final String? sessionFingerprint;

  bool matchesConfig(NotificationWorkerConfig config) =>
      sessionFingerprint != null &&
      sessionFingerprint == config.sessionFingerprint;

  Map<String, Object?> toJson() => {
    'pending': [for (final p in pending) p.toJson()],
    'nextWatermark': nextWatermark.toJson(),
    'sessionFingerprint': sessionFingerprint,
  };

  factory NotificationOutbox.fromJson(Map<String, Object?> j) =>
      NotificationOutbox(
        sessionFingerprint: j['sessionFingerprint'] as String?,
        pending: [
          for (final p in (j['pending'] as List))
            PendingSeriesNotification.fromJson(
              (p as Map).cast<String, Object?>(),
            ),
        ],
        nextWatermark: NewChapterWatermark.fromJson(
          (j['nextWatermark'] as Map).cast<String, Object?>(),
        ),
      );
}

/// Each value is one atomic JSON write, readable from any isolate.
class NotificationStateStore {
  NotificationStateStore(this._prefs);
  final SharedPreferences _prefs;

  static const _configKey = 'notif_worker_config';
  static const _tokenKey = 'notif_token_record';
  static const _cursorKey = 'notif_cursor';
  static const _outboxKey = 'notif_outbox';

  static Future<NotificationStateStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return NotificationStateStore(prefs);
  }

  Future<void> writeConfig(NotificationWorkerConfig config) async {
    if (!await _prefs.setString(_configKey, jsonEncode(config.toJson()))) {
      throw StateError('Failed to save notification worker config');
    }
  }

  NotificationWorkerConfig? readConfig() {
    final raw = _prefs.getString(_configKey);
    if (raw == null) return null;
    return NotificationWorkerConfig.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  /// Auth rotates independently of config and must have its own key.
  BackgroundTokenRecord? readTokenRecord() {
    final raw = _prefs.getString(_tokenKey);
    if (raw == null) return null;
    return BackgroundTokenRecord.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  Future<void> writeTokenRecord(BackgroundTokenRecord record) async {
    if (!await _prefs.setString(_tokenKey, jsonEncode(record.toJson()))) {
      throw StateError('Failed to save notification token record');
    }
  }

  /// A server mismatch resets detection state to avoid replaying or skipping chapters.
  NewChapterWatermark readWatermark(String serverId) {
    final raw = _prefs.getString(_cursorKey);
    if (raw == null) return const NewChapterWatermark();
    final j = (jsonDecode(raw) as Map).cast<String, Object?>();
    if (j['serverId'] != serverId) return const NewChapterWatermark();
    return NewChapterWatermark.fromJson(
      (j['watermark'] as Map).cast<String, Object?>(),
    );
  }

  Future<void> writeWatermark(String serverId, NewChapterWatermark wm) =>
      _prefs.setString(
        _cursorKey,
        jsonEncode({'serverId': serverId, 'watermark': wm.toJson()}),
      );

  NotificationOutbox? readOutbox() {
    final raw = _prefs.getString(_outboxKey);
    if (raw == null) return null;
    return NotificationOutbox.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  Future<void> writeOutbox(NotificationOutbox outbox) =>
      _prefs.setString(_outboxKey, jsonEncode(outbox.toJson()));

  Future<void> clearOutbox() => _prefs.remove(_outboxKey);

  String? get lastNotifiedAppVersion => _prefs.getString('notif_app_version');
  Future<void> setLastNotifiedAppVersion(String v) =>
      _prefs.setString('notif_app_version', v);

  int get lastExtensionUpdateCount => _prefs.getInt('notif_ext_count') ?? 0;
  Future<void> setLastExtensionUpdateCount(int c) =>
      _prefs.setInt('notif_ext_count', c);

  Future<void> clearSession() async {
    await _prefs.remove(_configKey);
    await _prefs.remove(_tokenKey);
    await clearState();
  }

  /// Clears detection state without touching worker config.
  Future<void> clearState() async {
    await _prefs.remove(_cursorKey);
    await _prefs.remove(_outboxKey);
  }
}
