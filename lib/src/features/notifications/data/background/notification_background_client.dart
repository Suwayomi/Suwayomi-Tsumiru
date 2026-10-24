// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../../../constants/app_distribution.dart';
import '../../../../constants/endpoints.dart';
import '../../../../utils/crash/diagnostics.dart';
import '../../../account/data/account_permission.dart';
import '../../../offline/data/background/background_chapter_fetch.dart';
import '../../../offline/data/background/background_endpoint.dart';
import '../../../offline/data/background/background_token_record.dart'
    show BackgroundTokenRecord, TokenBroker, applyIsolateCustomHeaders;

/// Persisted endpoint used by the provider-free background isolate.
class NotificationEndpoint {
  const NotificationEndpoint({
    required this.baseUrl,
    this.port,
    this.addPort = true,
    this.lanUrl,
    this.externalUrl,
  });

  /// Identity checks use the address verified by the foreground.
  final String baseUrl;
  final int? port;
  final bool addPort;

  /// Configured addresses for network selection; null for older persisted configs.
  final String? lanUrl, externalUrl;

  Future<NotificationEndpoint> forThisNetwork({
    required String source,
    @visibleForTesting Future<bool> Function(String url)? isReachable,
  }) async {
    final selected = await pickBackgroundServerBase(
      active: baseUrl,
      lanUrl: lanUrl,
      externalUrl: externalUrl,
      source: source,
      isReachable: isReachable,
    );
    return selected == baseUrl
        ? this
        : NotificationEndpoint(
            baseUrl: selected,
            port: port,
            addPort: addPort,
            lanUrl: lanUrl,
            externalUrl: externalUrl,
          );
  }

  String get graphqlUrl => Endpoints.baseApi(
    baseUrl: baseUrl,
    port: port,
    addPort: addPort,
    isGraphQl: true,
  );

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'port': port,
    'addPort': addPort,
    'lanUrl': lanUrl,
    'externalUrl': externalUrl,
  };

  factory NotificationEndpoint.fromJson(Map<String, Object?> j) =>
      NotificationEndpoint(
        baseUrl: j['baseUrl'] as String,
        port: (j['port'] as num?)?.toInt(),
        addPort: (j['addPort'] as bool?) ?? true,
        lanUrl: j['lanUrl'] as String?,
        externalUrl: j['externalUrl'] as String?,
      );
}

typedef NotifChapter = ({
  int id,
  int mangaId,
  double chapterNumber,
  String name,
  int fetchedAt,
  String mangaTitle,
  String? thumbnailUrl,
  Set<int> categoryIds,
});

typedef NewChaptersPage = ({
  List<NotifChapter> nodes,
  bool hasNextPage,
  String? endCursor,
});

/// Provider-free GraphQL client sharing versioned auth refresh through [TokenBroker].
class NotificationBackgroundClient {
  NotificationBackgroundClient({
    required this.endpoint,
    required BackgroundTokenRecord record,
    required this.broker,
    http.Client? httpClient,
    this.isCancelled,
    this.onDownloadPermissionDenied,
    this.admitDownload,
  }) : _record = record,
       _http = httpClient ?? http.Client();

  final NotificationEndpoint endpoint;
  final bool Function()? isCancelled;
  final Future<void> Function()? onDownloadPermissionDenied;
  final Future<bool> Function()? admitDownload;
  final TokenBroker broker;
  final http.Client _http;
  BackgroundTokenRecord _record;

  /// Returns live broker auth, including rotations made by the catch-up executor.
  BackgroundTokenRecord currentRecord() {
    final latest = broker.latest;
    if (latest != null &&
        latest.gen > _record.gen &&
        latest.sameIdentity(_record)) {
      _record = latest;
    }
    return _record;
  }

  static const Object _authError = gqlAuthError;
  static const Object _networkError = gqlNetworkError;

  // Retry ui_login once through the broker on 401; return null on auth, network, or server failure.
  Future<Map<String, Object?>?> _post(
    String query,
    Map<String, Object?> variables, {
    bool downloadOperation = false,
  }) async {
    final ahead = await broker.refreshIfDue(currentRecord());
    if (ahead.sameIdentity(_record)) _record = ahead;
    var res = await _raw(
      query,
      variables,
      _record.accessToken,
      downloadOperation: downloadOperation,
    );
    if (identical(res, _authError) && _record.authType == 'uiLogin') {
      final fresh = await broker.resolveAfter401(_record.accessToken ?? '');
      if (fresh != null) {
        final current = await broker.readCurrent();
        if (current == null || !current.sameIdentity(_record)) return null;
        _record = current;
        res = await _raw(
          query,
          variables,
          fresh,
          downloadOperation: downloadOperation,
        );
      } else {
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-graphql: '
          'refresh-failed transient=${broker.lastRefreshTransient}\n',
        );
      }
    } else if (identical(res, _authError)) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-graphql: '
        'auth-rejected authType=${_record.authType} (no refresh path)\n',
      );
    }
    return res is Map<String, Object?> ? res : null;
  }

  BackgroundServerTarget get _target => BackgroundServerTarget(
    serverBase: endpoint.baseUrl,
    port: endpoint.port,
    addPort: endpoint.addPort,
    client: _http,
    isCancelled: isCancelled,
    onNetworkError: (error) => recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-graphql: $error\n',
    ),
  );

  Future<Object?> _raw(
    String query,
    Map<String, Object?> variables,
    String? accessToken, {
    bool downloadOperation = false,
  }) async {
    try {
      return await postBackgroundGraphql(
        target: _target,
        record: _record,
        query: query,
        variables: variables,
        accessToken: accessToken,
      );
    } on AccountPermissionDenied {
      if (downloadOperation) rethrow;
      return _networkError;
    }
  }

  Future<bool> verifyDownloadAccess() async {
    if (admitDownload != null && !await admitDownload!()) return false;
    try {
      return await verifyBackgroundDownloadAccess(
        target: _target,
        record: currentRecord,
        broker: broker,
      );
    } on AccountPermissionDenied {
      if (!(isCancelled?.call() ?? false)) {
        await onDownloadPermissionDenied?.call();
      }
      return false;
    }
  }

  static const _newChaptersQuery = r'''
query NotifNewChapters($f: LongString!, $after: Cursor) {
  chapters(
    filter: { inLibrary: { equalTo: true }, isRead: { equalTo: false }, fetchedAt: { greaterThanOrEqualTo: $f } }
    order: [{ by: FETCHED_AT, byType: ASC }, { by: ID, byType: ASC }]
    first: 200
    after: $after
  ) {
    pageInfo { hasNextPage endCursor }
    nodes {
      id
      mangaId
      chapterNumber
      name
      fetchedAt
      manga { title thumbnailUrl categories { nodes { id } } }
    }
  }
}''';

  /// Unread library chapters since epoch-second string [fetchedAtGte], ascending by (fetchedAt, id); null on failure.
  Future<NewChaptersPage?> fetchNewChaptersPage({
    required String fetchedAtGte,
    String? after,
  }) async {
    final data = await _post(_newChaptersQuery, {
      'f': fetchedAtGte,
      'after': after,
    });
    final chapters = data?['chapters'] as Map<String, Object?>?;
    if (chapters == null) return null;
    final pageInfo = chapters['pageInfo'] as Map<String, Object?>?;
    final nodes = (chapters['nodes'] as List? ?? const []).cast<Object?>();
    return (
      nodes: [for (final n in nodes) _parseChapter(n as Map<String, Object?>)],
      hasNextPage: (pageInfo?['hasNextPage'] as bool?) ?? false,
      endCursor: pageInfo?['endCursor'] as String?,
    );
  }

  NotifChapter _parseChapter(Map<String, Object?> n) {
    final manga = n['manga'] as Map<String, Object?>?;
    final cats =
        ((manga?['categories'] as Map<String, Object?>?)?['nodes'] as List? ??
                const [])
            .cast<Object?>();
    return (
      id: (n['id'] as num).toInt(),
      mangaId: (n['mangaId'] as num).toInt(),
      chapterNumber: (n['chapterNumber'] as num?)?.toDouble() ?? -1,
      name: (n['name'] as String?) ?? '',
      fetchedAt: int.tryParse('${n['fetchedAt']}') ?? 0,
      mangaTitle: (manga?['title'] as String?) ?? '',
      thumbnailUrl: manga?['thumbnailUrl'] as String?,
      categoryIds: {
        for (final c in cats)
          ((c as Map<String, Object?>)['id'] as num).toInt(),
      },
    );
  }

  static const _maxFetchedQuery = r'''
query NotifMaxFetched {
  chapters(
    filter: { inLibrary: { equalTo: true } }
    order: [{ by: FETCHED_AT, byType: DESC }, { by: ID, byType: DESC }]
    first: 1
  ) { nodes { fetchedAt } }
}''';

  /// Highest library fetchedAt in epoch seconds; zero for an empty library.
  Future<int> serverMaxFetchedAt() async {
    final data = await _post(_maxFetchedQuery, const {});
    final nodes =
        ((data?['chapters'] as Map<String, Object?>?)?['nodes'] as List? ??
                const [])
            .cast<Object?>();
    if (nodes.isEmpty) return 0;
    return int.tryParse(
          '${(nodes.first as Map<String, Object?>)['fetchedAt']}',
        ) ??
        0;
  }

  static const _markReadMutation = r'''
mutation NotifMarkRead($ids: [Int!]!) {
  updateChapters(input: { ids: $ids, patch: { isRead: true } }) { clientMutationId }
}''';

  Future<bool> markRead(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return true;
    final data = await _post(_markReadMutation, {'ids': chapterIds});
    return data != null;
  }

  static const _enqueueMutation = r'''
mutation NotifEnqueue($ids: [Int!]!) {
  enqueueChapterDownloads(input: { ids: $ids }) { clientMutationId }
}''';

  Future<bool> enqueueDownloads(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return true;
    if (!await verifyDownloadAccess()) return false;
    try {
      final data = await _post(_enqueueMutation, {
        'ids': chapterIds,
      }, downloadOperation: true);
      return !(isCancelled?.call() ?? false) &&
          data?['enqueueChapterDownloads'] is Map;
    } on AccountPermissionDenied {
      if (!(isCancelled?.call() ?? false)) {
        await onDownloadPermissionDenied?.call();
      }
      return false;
    }
  }

  /// Cover paths already include /api; fetch failures fall back to text without a 401 retry.
  Future<List<int>?> fetchCover(String thumbnailUrl) async {
    final base = Endpoints.baseApi(
      baseUrl: endpoint.baseUrl,
      port: endpoint.port,
      addPort: endpoint.addPort,
      appendApiToUrl: false,
    );
    final url = '$base$thumbnailUrl';
    final headers = <String, String>{};
    switch (_record.authType) {
      case 'uiLogin':
        final token = _record.accessToken;
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      case 'basic':
        final cred = _record.basicCredential;
        if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
      case 'simpleLogin':
        final cookie = _record.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    }
    applyIsolateCustomHeaders(headers, _record.extraHeaders);
    try {
      final res = await _http.get(Uri.parse(url), headers: headers);
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  static const _extensionUpdatesQuery =
      'query { extensions(condition: { hasUpdate: true, isInstalled: true }) { totalCount } }';

  Future<int> countExtensionUpdates() async {
    final data = await _post(_extensionUpdatesQuery, const {});
    return ((data?['extensions'] as Map<String, Object?>?)?['totalCount']
                as num?)
            ?.toInt() ??
        0;
  }

  /// Public GitHub release version and page; null on failure.
  Future<({String version, String url})?> fetchLatestRelease() async {
    if (isGooglePlayBuild) return null;
    try {
      final res = await _http.get(
        Uri.parse(
          'https://api.github.com/repos/Suwayomi/Suwayomi-Tsumiru/releases/latest',
        ),
        headers: const {'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, Object?>;
      final tag = (j['tag_name'] as String?)?.replaceFirst('v', '');
      if (tag == null || tag.isEmpty) return null;
      return (version: tag, url: (j['html_url'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }
}
