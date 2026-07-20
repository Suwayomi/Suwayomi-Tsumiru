// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'background_token_record.dart';

class BackgroundWorkOrder {
  const BackgroundWorkOrder({
    required this.chapterIds,
    required this.mangaIdByChapter,
    required this.serverBase,
    required this.port,
    required this.addPort,
    required this.wifiOnly,
    required this.auth,
    required this.baseDir,
    this.generationByChapter = const {},
    this.rootIsolateToken = 0,
  });

  final List<int> chapterIds;
  final Map<int, int> mangaIdByChapter;

  /// Per-chapter download generation (bumped on delete). The worker echoes it on
  /// every event so the main isolate can drop a stale generation's events.
  final Map<int, int> generationByChapter;
  final String serverBase;
  final int? port;
  final bool addPort;
  final bool wifiOnly;
  final BackgroundTokenRecord auth;

  /// Absolute offline base directory (`<appSupport>/offline`), resolved by the
  /// MAIN isolate via path_provider and handed to the worker so it stays
  /// plugin-free (builds [OfflinePaths]/[IoOfflinePageStore] from this string
  /// with only dart:io).
  final String baseDir;

  /// Vestigial — the plugin-free worker touches no platform channels so this
  /// is unused. Kept only so the JSON shape stays backward-compatible;
  /// defaults to 0 and is ignored.
  final int rootIsolateToken;

  Map<String, Object?> toJson() => {
        'chapterIds': chapterIds,
        'mangaIdByChapter':
            mangaIdByChapter.map((k, v) => MapEntry(k.toString(), v)),
        'generationByChapter':
            generationByChapter.map((k, v) => MapEntry(k.toString(), v)),
        'serverBase': serverBase,
        'port': port,
        'addPort': addPort,
        'wifiOnly': wifiOnly,
        'auth': auth.toJson(),
        'baseDir': baseDir,
        'rootIsolateToken': rootIsolateToken,
      };

  factory BackgroundWorkOrder.fromJson(Map<String, Object?> j) =>
      BackgroundWorkOrder(
        chapterIds: (j['chapterIds'] as List).cast<int>(),
        mangaIdByChapter: (j['mangaIdByChapter'] as Map)
            .map((k, v) => MapEntry(int.parse(k as String), v as int)),
        generationByChapter: (j['generationByChapter'] as Map?)
                ?.map((k, v) => MapEntry(int.parse(k as String), v as int)) ??
            const {},
        serverBase: j['serverBase'] as String,
        port: j['port'] as int?,
        addPort: j['addPort'] as bool,
        wifiOnly: j['wifiOnly'] as bool,
        auth: BackgroundTokenRecord.fromJson(
            j['auth'] as Map<String, Object?>),
        baseDir: j['baseDir'] as String? ?? '',
        rootIsolateToken: j['rootIsolateToken'] as int? ?? 0,
      );
}
