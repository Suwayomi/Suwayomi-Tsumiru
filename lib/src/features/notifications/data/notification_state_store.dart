// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../offline/data/background/background_token_record.dart';
import '../domain/new_chapter_detection.dart';
import 'background/notification_background_client.dart';

/// Everything the headless worker needs to reach the server and decide what to
/// notify. Written by the app (on enable / settings change / auth rotation);
/// read fresh by the WorkManager isolate. `serverId` scopes the cursor so a
/// server switch can't replay or skip chapters.
class NotificationWorkerConfig {
  const NotificationWorkerConfig({
    required this.serverId,
    required this.endpoint,
    required this.newChaptersEnabled,
    required this.includedCategoryIds,
    required this.excludedCategoryIds,
    required this.hideContent,
    this.appUpdatesEnabled = false,
    this.extensionUpdatesEnabled = false,
    this.appVersion = '',
  });

  final String serverId;
  final NotificationEndpoint endpoint;
  final bool newChaptersEnabled;
  final bool appUpdatesEnabled;
  final bool extensionUpdatesEnabled;

  /// The installed app version, so the worker can compare against the latest
  /// release without a plugin call in the isolate.
  final String appVersion;

  /// The periodic job runs when ANY check is on.
  bool get anyEnabled =>
      newChaptersEnabled || appUpdatesEnabled || extensionUpdatesEnabled;

  /// Empty include = all categories; anything in exclude is dropped.
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
      };

  factory NotificationWorkerConfig.fromJson(Map<String, Object?> j) =>
      NotificationWorkerConfig(
        serverId: j['serverId'] as String,
        endpoint: NotificationEndpoint.fromJson(
            (j['endpoint'] as Map).cast<String, Object?>()),
        newChaptersEnabled: (j['newChaptersEnabled'] as bool?) ?? false,
        appUpdatesEnabled: (j['appUpdatesEnabled'] as bool?) ?? false,
        extensionUpdatesEnabled: (j['extensionUpdatesEnabled'] as bool?) ?? false,
        appVersion: (j['appVersion'] as String?) ?? '',
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

  /// Category scope as an allow-set for [detectNewChapters], or null (= all)
  /// when there's no include list and nothing excluded. Computed against the
  /// live library membership the worker fetches.
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

/// One series pending in the durable outbox — enough to (re)publish the
/// notification without another network call.
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

  /// The earliest-by-number new chapter — the "open first new chapter" target.
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
          for (final id in (j['chapterIds'] as List)) (id as num).toInt()
        ],
        chapterNumbers: [
          for (final n in (j['chapterNumbers'] as List)) (n as num).toDouble()
        ],
        firstChapterId: (j['firstChapterId'] as num).toInt(),
        totalCount: (j['totalCount'] as num).toInt(),
      );
}

/// The durable outbox: the batch to publish plus the advanced cursor, written
/// as ONE atomic value BEFORE publishing. A crash after this point re-publishes
/// (stable ids + onlyAlertOnce → a replace, not a re-buzz), never loses the
/// cursor advance, and never drops a detected chapter.
class NotificationOutbox {
  const NotificationOutbox({required this.pending, required this.nextWatermark});
  final List<PendingSeriesNotification> pending;
  final NewChapterWatermark nextWatermark;

  Map<String, Object?> toJson() => {
        'pending': [for (final p in pending) p.toJson()],
        'nextWatermark': nextWatermark.toJson(),
      };

  factory NotificationOutbox.fromJson(Map<String, Object?> j) =>
      NotificationOutbox(
        pending: [
          for (final p in (j['pending'] as List))
            PendingSeriesNotification.fromJson((p as Map).cast<String, Object?>())
        ],
        nextWatermark: NewChapterWatermark.fromJson(
            (j['nextWatermark'] as Map).cast<String, Object?>()),
      );
}

/// SharedPreferences-backed store, readable from any isolate. Each value is a
/// single JSON string, so every write is atomic — enough for the outbox
/// protocol without a database.
class NotificationStateStore {
  NotificationStateStore(this._prefs);
  final SharedPreferences _prefs;

  static const _configKey = 'notif_worker_config';
  static const _tokenKey = 'notif_token_record';
  static const _cursorKey = 'notif_cursor';
  static const _outboxKey = 'notif_outbox';

  static Future<NotificationStateStore> open() async =>
      NotificationStateStore(await SharedPreferences.getInstance());

  Future<void> writeConfig(NotificationWorkerConfig config) =>
      _prefs.setString(_configKey, jsonEncode(config.toJson()));

  NotificationWorkerConfig? readConfig() {
    final raw = _prefs.getString(_configKey);
    if (raw == null) return null;
    return NotificationWorkerConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>());
  }

  /// The auth record rotates independently of config (a ui_login refresh bumps
  /// its gen), so it lives under its own key — the broker reads/writes it here.
  BackgroundTokenRecord? readTokenRecord() {
    final raw = _prefs.getString(_tokenKey);
    if (raw == null) return null;
    return BackgroundTokenRecord.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>());
  }

  Future<void> writeTokenRecord(BackgroundTokenRecord record) =>
      _prefs.setString(_tokenKey, jsonEncode(record.toJson()));

  /// The cursor for [serverId]; resets to empty when the stored cursor belongs
  /// to a different server (switch → no replay/skip).
  NewChapterWatermark readWatermark(String serverId) {
    final raw = _prefs.getString(_cursorKey);
    if (raw == null) return const NewChapterWatermark();
    final j = (jsonDecode(raw) as Map).cast<String, Object?>();
    if (j['serverId'] != serverId) return const NewChapterWatermark();
    return NewChapterWatermark.fromJson(
        (j['watermark'] as Map).cast<String, Object?>());
  }

  Future<void> writeWatermark(String serverId, NewChapterWatermark wm) =>
      _prefs.setString(_cursorKey,
          jsonEncode({'serverId': serverId, 'watermark': wm.toJson()}));

  NotificationOutbox? readOutbox() {
    final raw = _prefs.getString(_outboxKey);
    if (raw == null) return null;
    return NotificationOutbox.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>());
  }

  Future<void> writeOutbox(NotificationOutbox outbox) =>
      _prefs.setString(_outboxKey, jsonEncode(outbox.toJson()));

  Future<void> clearOutbox() => _prefs.remove(_outboxKey);

  // Dedup for the app/extension update checks — only notify when the state
  // actually changes, not every wake.
  String? get lastNotifiedAppVersion => _prefs.getString('notif_app_version');
  Future<void> setLastNotifiedAppVersion(String v) =>
      _prefs.setString('notif_app_version', v);

  int get lastExtensionUpdateCount => _prefs.getInt('notif_ext_count') ?? 0;
  Future<void> setLastExtensionUpdateCount(int c) =>
      _prefs.setInt('notif_ext_count', c);

  /// Reset detection state (server switch / disable) without touching config.
  Future<void> clearState() async {
    await _prefs.remove(_cursorKey);
    await _prefs.remove(_outboxKey);
  }
}
