// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../constants/db_keys.dart';
import '../../../notifications/domain/new_chapter_detection.dart';
import '../offline_types.dart';

/// The background download step's read-only stand-in for drift: what the
/// foreground knew when it last ran. Drift stays single-writer; the worker
/// never opens it.
class CatchupMangaSpec {
  const CatchupMangaSpec({
    required this.mangaId,
    required this.keepRule,
    required this.keepUnreadCount,
    required this.onDeviceChapterIds,
    required this.pinnedChapterIds,
    this.chapterGenerations = const {},
  });

  final int mangaId;
  final OfflineKeepRule keepRule;
  final int keepUnreadCount;
  final Set<int> onDeviceChapterIds;
  final Set<int> pinnedChapterIds;

  /// Download generation per chapter, for the ones that have been deleted at
  /// least once. Staging the worker writes has to carry the generation its row
  /// actually holds, or the commit at launch rejects it as belonging to a
  /// download that was superseded — and the work is thrown away after the
  /// obligation has already been marked done. Absent means 0, the default for
  /// a chapter nobody has deleted.
  final Map<int, int> chapterGenerations;

  /// The generation to stamp on a download of [chapterId].
  int generationOf(int chapterId) => chapterGenerations[chapterId] ?? 0;

  Map<String, Object?> toJson() => {
    'mangaId': mangaId,
    // By NAME, not index — the enum may gain values and a spec file can
    // outlive the app version that wrote it.
    'keepRule': keepRule.name,
    'keepUnreadCount': keepUnreadCount,
    'onDevice': onDeviceChapterIds.toList(),
    'pinned': pinnedChapterIds.toList(),
    'gens': {for (final e in chapterGenerations.entries) '${e.key}': e.value},
  };

  factory CatchupMangaSpec.fromJson(Map<String, Object?> j) => CatchupMangaSpec(
    mangaId: (j['mangaId'] as num).toInt(),
    keepRule:
        OfflineKeepRule.values.asNameMap()[j['keepRule']] ??
        OfflineKeepRule.off,
    keepUnreadCount: (j['keepUnreadCount'] as num?)?.toInt() ?? 0,
    onDeviceChapterIds: {
      for (final id in (j['onDevice'] as List? ?? const []))
        (id as num).toInt(),
    },
    pinnedChapterIds: {
      for (final id in (j['pinned'] as List? ?? const [])) (id as num).toInt(),
    },
    chapterGenerations: {
      for (final e in (j['gens'] as Map? ?? const {}).entries)
        if (int.tryParse('${e.key}') case final id?)
          id: (e.value as num).toInt(),
    },
  );
}

class CatchupWorkSpec {
  const CatchupWorkSpec({
    required this.serverId,
    required this.wifiOnly,
    required this.storageCapEnabled,
    required this.storageCapBytes,
    required this.manga,
    this.usedBytes = 0,
  });

  final String serverId;
  final bool wifiOnly;
  final bool storageCapEnabled;
  final int storageCapBytes;
  final List<CatchupMangaSpec> manga;

  /// On-device bytes when the spec was written — the executor's cap baseline.
  final int usedBytes;

  Set<int> get keepRuleMangaIds => {for (final m in manga) m.mangaId};

  Map<String, Object?> toJson() => {
    'serverId': serverId,
    'wifiOnly': wifiOnly,
    'storageCapEnabled': storageCapEnabled,
    'storageCapBytes': storageCapBytes,
    'usedBytes': usedBytes,
    'manga': [for (final m in manga) m.toJson()],
  };

  factory CatchupWorkSpec.fromJson(Map<String, Object?> j) => CatchupWorkSpec(
    serverId: j['serverId'] as String,
    wifiOnly: (j['wifiOnly'] as bool?) ?? true,
    storageCapEnabled: (j['storageCapEnabled'] as bool?) ?? false,
    storageCapBytes: (j['storageCapBytes'] as num?)?.toInt() ?? 0,
    usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
    manga: [
      for (final m in (j['manga'] as List? ?? const []))
        CatchupMangaSpec.fromJson((m as Map).cast<String, Object?>()),
    ],
  );
}

/// The download side's cursor and obligations, written as ONE JSON value so
/// every transition is atomic — the ledger and cursor can never disagree after
/// a crash (the completion log wins where they overlap; see prune()).
class CatchupLedger {
  const CatchupLedger({
    this.cursor = const NewChapterWatermark(),
    this.pendingDownloads = const {},
    this.pendingServerFetch = const {},
    this.serverFetchRetries = const {},
    this.downloadRetries = const {},
    this.backfilledMangaIds = const {},
  });

  final NewChapterWatermark cursor;

  /// chapterId → mangaId, resolved but not yet completed on device.
  final Map<int, int> pendingDownloads;

  /// chapterId → mangaId, enqueued server-side; collect next run.
  final Map<int, int> pendingServerFetch;

  /// chapterId → runs spent asking the server to fetch it from the source;
  /// expired entries surface via the launch banner instead of retrying forever
  /// against a dead source.
  final Map<int, int> serverFetchRetries;

  /// chapterId → attempts spent pulling it from the server onto this device.
  /// Separate from [serverFetchRetries] on purpose: the two hops fail for
  /// different reasons, and one budget shared between them meant a slow source
  /// could exhaust the chapter before the device ever tried.
  final Map<int, int> downloadRetries;

  /// Manga the executor has already given one full chapter-list pass since it
  /// entered the spec. The feed-based cursor above only ever surfaces chapters
  /// that are NEW since it was seeded — a manga's pre-existing backlog (e.g. a
  /// keep rule just turned on for it) never appears there and would otherwise
  /// sit untouched until the next foreground launch pass, which is the one
  /// path that fetches a manga's full list rather than diffing the feed. Once
  /// a manga is in this set its remaining gaps live in [pendingDownloads] /
  /// [pendingServerFetch] like any other obligation, so it only needs the one
  /// pass.
  final Set<int> backfilledMangaIds;

  CatchupLedger copyWith({
    NewChapterWatermark? cursor,
    Map<int, int>? pendingDownloads,
    Map<int, int>? pendingServerFetch,
    Map<int, int>? serverFetchRetries,
    Map<int, int>? downloadRetries,
    Set<int>? backfilledMangaIds,
  }) => CatchupLedger(
    cursor: cursor ?? this.cursor,
    pendingDownloads: pendingDownloads ?? this.pendingDownloads,
    pendingServerFetch: pendingServerFetch ?? this.pendingServerFetch,
    serverFetchRetries: serverFetchRetries ?? this.serverFetchRetries,
    downloadRetries: downloadRetries ?? this.downloadRetries,
    backfilledMangaIds: backfilledMangaIds ?? this.backfilledMangaIds,
  );

  Map<String, Object?> toJson() => {
    'cursor': cursor.toJson(),
    'pendingDownloads': _mapToJson(pendingDownloads),
    'pendingServerFetch': _mapToJson(pendingServerFetch),
    'serverFetchRetries': _mapToJson(serverFetchRetries),
    'downloadRetries': _mapToJson(downloadRetries),
    'backfilledMangaIds': backfilledMangaIds.toList(),
  };

  factory CatchupLedger.fromJson(Map<String, Object?> j) => CatchupLedger(
    cursor: NewChapterWatermark.fromJson(
      (j['cursor'] as Map? ?? const {}).cast<String, dynamic>(),
    ),
    pendingDownloads: _mapFromJson(j['pendingDownloads']),
    pendingServerFetch: _mapFromJson(j['pendingServerFetch']),
    serverFetchRetries: _mapFromJson(j['serverFetchRetries']),
    downloadRetries: _mapFromJson(j['downloadRetries']),
    backfilledMangaIds: {
      for (final id in (j['backfilledMangaIds'] as List? ?? const []))
        (id as num).toInt(),
    },
  );

  static Map<String, Object?> _mapToJson(Map<int, int> m) => {
    for (final e in m.entries) '${e.key}': e.value,
  };

  static Map<int, int> _mapFromJson(Object? raw) => {
    for (final e in (raw as Map? ?? const {}).entries)
      int.parse('${e.key}'): (e.value as num).toInt(),
  };
}

/// SharedPreferences-backed, single-JSON-per-key (atomic writes), readable
/// from the WorkManager isolate — the NotificationStateStore pattern.
class CatchupStateStore {
  CatchupStateStore(this._prefs);
  final SharedPreferences _prefs;

  static const _specKey = 'catchup_work_spec';
  static const _ledgerKey = 'catchup_ledger';
  static const _enabledKey = 'catchup_bg_enabled';
  static const _downloadEnabledKey = 'catchup_bg_download_enabled';

  /// The worker isolate and the app share these keys through separate
  /// SharedPreferences caches; open() reloads so a run never plans from — or
  /// writes back — another isolate's stale snapshot.
  static Future<CatchupStateStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return CatchupStateStore(prefs);
  }

  // Default ON: keep rules are an explicit per-series "keep this on my device"
  // opt-in, and without them this is a no-op. (Komikku defaults its GLOBAL
  // auto-download off — a deliberate deviation, flagged in the design doc.)
  bool get enabled => _prefs.getBool(_enabledKey) ?? true;
  Future<void> setEnabled(bool v) => _prefs.setBool(_enabledKey, v);

  /// Whether the background run also fetches chapter files, or only detects
  /// and queues them (leaving the actual download for the next foreground
  /// session). Default ON — matches the behavior before this toggle existed.
  bool get downloadEnabled => _prefs.getBool(_downloadEnabledKey) ?? true;
  Future<void> setDownloadEnabled(bool v) =>
      _prefs.setBool(_downloadEnabledKey, v);

  /// The offline catalog's own server-instance id — what [writeSpec]'s
  /// [CatchupWorkSpec.serverId] is actually stamped with. NOT the same value
  /// as [NotificationWorkerConfig.serverId] (a "url|port" string scoping the
  /// unrelated notification cursor) — the executor must not cross-check the
  /// spec against that instead, or the spec looks perpetually stale.
  String? get catalogServerId =>
      _prefs.getString(DBKeys.offlineCatalogServerId.name);

  Future<void> writeSpec(CatchupWorkSpec spec) =>
      _prefs.setString(_specKey, jsonEncode(spec.toJson()));

  CatchupWorkSpec? readSpec() {
    final raw = _prefs.getString(_specKey);
    if (raw == null) return null;
    return CatchupWorkSpec.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  /// Ledger scoped to [serverId] — a server switch starts from empty, like the
  /// notification cursor.
  CatchupLedger readLedger(String serverId) {
    final raw = _prefs.getString(_ledgerKey);
    if (raw == null) return const CatchupLedger();
    final j = (jsonDecode(raw) as Map).cast<String, Object?>();
    if (j['serverId'] != serverId) return const CatchupLedger();
    return CatchupLedger.fromJson((j['ledger'] as Map).cast<String, Object?>());
  }

  Future<void> writeLedger(String serverId, CatchupLedger ledger) =>
      _prefs.setString(
        _ledgerKey,
        jsonEncode({'serverId': serverId, 'ledger': ledger.toJson()}),
      );

  /// Server switch / sign-out / catalog clear: the worker must not outlive its
  /// world. The enabled flag survives (it's the user's setting).
  Future<void> clearState() async {
    await _prefs.remove(_specKey);
    await _prefs.remove(_ledgerKey);
  }
}
