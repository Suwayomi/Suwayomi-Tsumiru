// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../../../offline/data/background/background_token_record.dart';

/// Where + how the background worker reaches the server. Persisted so the
/// WorkManager isolate (no Riverpod, no widget tree) can rebuild it.
class NotificationEndpoint {
  const NotificationEndpoint({
    required this.baseUrl,
    this.port,
    this.addPort = true,
  });

  final String baseUrl;
  final int? port;
  final bool addPort;

  String get graphqlUrl => Endpoints.baseApi(
        baseUrl: baseUrl,
        port: port,
        addPort: addPort,
        isGraphQl: true,
      );

  Map<String, Object?> toJson() =>
      {'baseUrl': baseUrl, 'port': port, 'addPort': addPort};

  factory NotificationEndpoint.fromJson(Map<String, Object?> j) =>
      NotificationEndpoint(
        baseUrl: j['baseUrl'] as String,
        port: (j['port'] as num?)?.toInt(),
        addPort: (j['addPort'] as bool?) ?? true,
      );
}

/// A new chapter as the notifier needs it (detection fields + display fields).
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

/// Provider-free authenticated GraphQL for the background notification worker.
/// Reuses the download worker's proven [BackgroundTokenRecord] + [TokenBroker]
/// (auth modes + gen-versioned 401 refresh), so nothing here touches Riverpod.
class NotificationBackgroundClient {
  NotificationBackgroundClient({
    required this.endpoint,
    required BackgroundTokenRecord record,
    required this.broker,
    http.Client? httpClient,
  })  : _record = record,
        _http = httpClient ?? http.Client();

  final NotificationEndpoint endpoint;
  final TokenBroker broker;
  final http.Client _http;
  BackgroundTokenRecord _record;

  static const Object _authError = Object();
  static const Object _networkError = Object();

  /// One raw GraphQL POST, retrying once through the broker on a ui_login 401.
  /// Returns the `data` map, or null on auth-dead / network / server error.
  Future<Map<String, Object?>?> _post(
      String query, Map<String, Object?> variables) async {
    var res = await _raw(query, variables, _record.accessToken);
    if (identical(res, _authError) && _record.authType == 'uiLogin') {
      final fresh = await broker.resolveAfter401(_record.accessToken ?? '');
      if (fresh != null) {
        _record = await broker.read();
        res = await _raw(query, variables, fresh);
      }
    }
    return res is Map<String, Object?> ? res : null;
  }

  Future<Object?> _raw(
      String query, Map<String, Object?> variables, String? accessToken) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    _applyAuth(headers, accessToken);
    try {
      final res = await _http.post(
        Uri.parse(endpoint.graphqlUrl),
        headers: headers,
        body: jsonEncode({'query': query, 'variables': variables}),
      );
      if (res.statusCode == 401 || res.statusCode == 403) return _authError;
      if (res.statusCode != 200) return _networkError;
      final decoded = jsonDecode(res.body) as Map<String, Object?>;
      return decoded['data'] as Map<String, Object?>?;
    } on SocketException {
      return _networkError;
    } catch (_) {
      return _networkError;
    }
  }

  void _applyAuth(Map<String, String> headers, String? accessToken) {
    switch (_record.authType) {
      case 'uiLogin':
        if (accessToken != null && accessToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $accessToken';
        }
      case 'basic':
        final cred = _record.basicCredential;
        if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
      case 'simpleLogin':
        final cookie = _record.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
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

  /// One page of unread, in-library chapters fetched at/after [fetchedAtGte]
  /// (a LongString epoch), ascending by (fetchedAt, id). Null on failure.
  Future<NewChaptersPage?> fetchNewChaptersPage({
    required String fetchedAtGte,
    String? after,
  }) async {
    final data = await _post(
        _newChaptersQuery, {'f': fetchedAtGte, 'after': after});
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
    final cats = ((manga?['categories'] as Map<String, Object?>?)?['nodes']
                as List? ??
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
        for (final c in cats) ((c as Map<String, Object?>)['id'] as num).toInt(),
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

  /// The server's current highest in-library `fetchedAt` (LongString), for
  /// first-enable initialization — so we neither dump the backlog nor miss the
  /// next fetch. 0 when the library has no chapters yet.
  Future<int> serverMaxFetchedAt() async {
    final data = await _post(_maxFetchedQuery, const {});
    final nodes =
        ((data?['chapters'] as Map<String, Object?>?)?['nodes'] as List? ??
                const [])
            .cast<Object?>();
    if (nodes.isEmpty) return 0;
    return int.tryParse(
            '${(nodes.first as Map<String, Object?>)['fetchedAt']}') ??
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
    final data = await _post(_enqueueMutation, {'ids': chapterIds});
    return data != null;
  }

  /// Fetch a manga cover's bytes for the per-series notification, mirroring
  /// `fetchOfflinePageBytes`: base API without `/api` (the thumbnail path carries
  /// it), ui_login as `?token=`, basic/simpleLogin via headers. Best-effort — a
  /// failed cover just falls back to a text notification, so no 401 retry.
  Future<List<int>?> fetchCover(String thumbnailUrl) async {
    final base = Endpoints.baseApi(
      baseUrl: endpoint.baseUrl,
      port: endpoint.port,
      addPort: endpoint.addPort,
      appendApiToUrl: false,
    );
    var url = '$base$thumbnailUrl';
    final headers = <String, String>{};
    switch (_record.authType) {
      case 'uiLogin':
        final token = _record.accessToken;
        if (token != null && token.isNotEmpty) {
          final sep = url.contains('?') ? '&' : '?';
          url = '$url${sep}token=${Uri.encodeQueryComponent(token)}';
        }
      case 'basic':
        final cred = _record.basicCredential;
        if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
      case 'simpleLogin':
        final cookie = _record.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    }
    try {
      final res = await _http.get(Uri.parse(url), headers: headers);
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  static const _extensionUpdatesQuery =
      'query { extensions(condition: { hasUpdate: true, isInstalled: true }) { totalCount } }';

  /// How many installed extensions have an update available (server-tracked).
  Future<int> countExtensionUpdates() async {
    final data = await _post(_extensionUpdatesQuery, const {});
    return ((data?['extensions'] as Map<String, Object?>?)?['totalCount']
                as num?)
            ?.toInt() ??
        0;
  }

  /// The latest Tsumiru release tag + its page, from the public GitHub API (no
  /// auth, no server). Null on any failure.
  Future<({String version, String url})?> fetchLatestRelease() async {
    try {
      final res = await _http.get(
        Uri.parse(
            'https://api.github.com/repos/Suwayomi/Suwayomi-Tsumiru/releases/latest'),
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
