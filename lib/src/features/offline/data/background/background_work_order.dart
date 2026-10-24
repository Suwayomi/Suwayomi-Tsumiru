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
    this.attemptId,
    this.catalogServerId,
    this.identityEpoch = 0,
    this.lanUrl,
    this.externalUrl,
  });

  final String? attemptId;
  final String? catalogServerId;
  final int identityEpoch;
  final List<int> chapterIds;
  final Map<int, int> mangaIdByChapter;

  /// Worker events echo this generation so main rejects pre-delete events.
  final Map<int, int> generationByChapter;

  /// Verified address anchors identity checks even if transport changes.
  final String serverBase;

  /// Null in legacy orders; otherwise transport can follow network changes.
  final String? lanUrl, externalUrl;
  final int? port;
  final bool addPort;
  final bool wifiOnly;
  final BackgroundTokenRecord auth;

  /// Resolved on the main isolate because path_provider requires platform channels.
  final String baseDir;

  /// Ignored; retained only for backward-compatible JSON.
  final int rootIsolateToken;

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'catalogServerId': catalogServerId,
    'identityEpoch': identityEpoch,
    'chapterIds': chapterIds,
    'mangaIdByChapter': mangaIdByChapter.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'generationByChapter': generationByChapter.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'serverBase': serverBase,
    'lanUrl': lanUrl,
    'externalUrl': externalUrl,
    'port': port,
    'addPort': addPort,
    'wifiOnly': wifiOnly,
    'auth': auth.toJson(),
    'baseDir': baseDir,
    'rootIsolateToken': rootIsolateToken,
  };

  factory BackgroundWorkOrder.fromJson(Map<String, Object?> j) =>
      BackgroundWorkOrder(
        attemptId: j['attemptId'] as String?,
        catalogServerId: j['catalogServerId'] as String?,
        identityEpoch: (j['identityEpoch'] as num?)?.toInt() ?? 0,
        chapterIds: (j['chapterIds'] as List).cast<int>(),
        mangaIdByChapter: (j['mangaIdByChapter'] as Map).map(
          (k, v) => MapEntry(int.parse(k as String), v as int),
        ),
        generationByChapter:
            (j['generationByChapter'] as Map?)?.map(
              (k, v) => MapEntry(int.parse(k as String), v as int),
            ) ??
            const {},
        serverBase: j['serverBase'] as String,
        lanUrl: j['lanUrl'] as String?,
        externalUrl: j['externalUrl'] as String?,
        port: j['port'] as int?,
        addPort: j['addPort'] as bool,
        wifiOnly: j['wifiOnly'] as bool,
        auth: BackgroundTokenRecord.fromJson(j['auth'] as Map<String, Object?>),
        baseDir: j['baseDir'] as String? ?? '',
        rootIsolateToken: j['rootIsolateToken'] as int? ?? 0,
      );
}

const kNotificationIconMetaData = 'app.tsumiru.NOTIFICATION_ICON';
