// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../../../../utils/network/gateway_status.dart';
import '../chapter_download_engine.dart';
import '../offline_download_providers.dart' show pageImageExt;
import '../offline_page_store.dart';
import 'background_token_record.dart';

/// One client for the whole background run. `http.get`/`http.post` open and
/// close a connection per call, so a catch-up batch paid a fresh TLS handshake
/// for every page it fetched. Lives as long as the isolate does.
final http.Client backgroundHttpClient = http.Client();

/// Bound on every call through this file. None of `package:http`'s calls time
/// out on their own, and this executor holds the shared `.bg_lock` file for
/// its whole run — a proxy/tunnel that accepts a connection but never replies
/// would hang a request forever, which means the lock is NEVER released, which
/// means the foreground-service worker can never acquire it either: it starts,
/// fails to get the lock, stops, and whatever re-triggers it starts the same
/// failed attempt again — the notification flashing on and off with nothing
/// ever reaching a chapter, and nothing logged, because nothing here ever
/// throws to report through.
const _httpTimeout = Duration(seconds: 30);

/// Server coordinates for the isolate-side fetch paths — the work-order fields
/// the FGS uses, shared with the WorkManager catch-up executor.
class BackgroundServerTarget {
  const BackgroundServerTarget({
    required this.serverBase,
    required this.port,
    required this.addPort,
  });
  final String serverBase;
  final int? port;
  final bool addPort;

  String get graphql => Endpoints.baseApi(
    baseUrl: serverBase,
    port: port,
    addPort: addPort,
    isGraphQl: true,
  );

  String get pageBase => Endpoints.baseApi(
    baseUrl: serverBase,
    port: port,
    addPort: addPort,
    appendApiToUrl: false,
  );
}

/// Sentinel: 401/403 — distinct from "no pages / other error" (empty list).
const Object gqlAuthError = Object();

/// Sentinel: server unreachable (transient) — the caller parks, doesn't error.
const Object gqlNetworkError = Object();

/// The app's auth modes on a hand-rolled request (uiLogin Bearer, basic,
/// simpleLogin cookie).
void applyBackgroundAuthHeaders(
  Map<String, String> headers,
  BackgroundTokenRecord record, {
  String? accessToken,
}) {
  switch (record.authType) {
    case 'uiLogin':
      final token = accessToken ?? record.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    case 'basic':
      final cred = record.basicCredential;
      if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
    case 'simpleLogin':
      final cookie = record.simpleCookie;
      if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
  }
}

/// One authenticated GraphQL POST. Returns the decoded `data` map,
/// [gqlAuthError], or [gqlNetworkError]; null on other failures.
Future<Object?> postBackgroundGraphql({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord record,
  required String query,
  required Map<String, Object?> variables,
  String? accessToken,
}) async {
  final headers = <String, String>{'Content-Type': 'application/json'};
  applyBackgroundAuthHeaders(headers, record, accessToken: accessToken);
  try {
    final res = await backgroundHttpClient
        .post(
          Uri.parse(target.graphql),
          headers: headers,
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(_httpTimeout);
    if (res.statusCode == 401 || res.statusCode == 403) return gqlAuthError;
    // A proxy answering for a dead origin is an outage, not a bad request —
    // the same rule the foreground worker and the app itself use.
    if (isGatewayStatus(res.statusCode)) return gqlNetworkError;
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body) as Map<String, Object?>;
    return decoded['data'];
  } on SocketException {
    return gqlNetworkError;
  } on TimeoutException {
    return gqlNetworkError;
  } catch (_) {
    return null;
  }
}

/// A chapter's page URLs: the list on success, empty on terminal failure, null
/// when the server was unreachable or a 401 could not be resolved. Retries
/// once through the broker on 401.
Future<List<String>?> resolveChapterPageUrls({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  required int chapterId,
}) async {
  const query =
      'mutation GetChapterPages(\$input: FetchChapterPagesInput!){ fetchChapterPages(input: \$input){ pages } }';
  Future<Object?> post(String? accessToken) => postBackgroundGraphql(
    target: target,
    record: record(),
    query: query,
    variables: {
      'input': {'chapterId': chapterId},
    },
    accessToken: accessToken,
  );

  var result = await post(null);
  if (result == gqlAuthError && record().authType == 'uiLogin') {
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    if (newAccess != null) {
      result = await post(newAccess);
    } else if (broker.lastRefreshTransient) {
      // The refresh call itself couldn't reach the server — likely the same
      // blip that produced the 401 in the first place (e.g. right after the
      // device reconnects). Park instead of condemning the chapter outright.
      return null;
    }
  }
  // An auth failure that survives the retry above (the refresh succeeded but
  // the retried call 401'd again, or the refresh itself failed non-
  // transiently) used to fall all the way through to the empty-list return
  // below — indistinguishable from "the server answered, this chapter truly
  // has no pages". The FGS worker treats an empty list as terminal and marks
  // the chapter `error` on the spot (download_task_handler.dart), so a token
  // that was merely stale right after a reconnect condemned the chapter
  // outright instead of getting the park-and-retry treatment every other
  // ambiguous failure in this file gets.
  if (result == gqlNetworkError || result == gqlAuthError) return null;
  if (result is Map<String, Object?>) {
    final pages =
        (result['fetchChapterPages'] as Map<String, Object?>?)?['pages'];
    if (pages is List) return pages.cast<String>();
  }
  return const <String>[];
}

/// The page-download engine over the isolate-side auth — shared verbatim
/// between the FGS worker and the catch-up executor so the two paths cannot
/// drift.
ChapterDownloadEngine buildBackgroundEngine({
  required OfflinePageStore store,
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  int parallelPageLimit = 5,
}) => ChapterDownloadEngine(
  writePage: store,
  parallelPageLimit: parallelPageLimit,
  fetchPage: (pageUrl) async {
    final r = record();
    var fetchUrl = '${target.pageBase}$pageUrl';
    final headers = <String, String>{};
    switch (r.authType) {
      case 'basic':
        final cred = r.basicCredential;
        if (cred != null && cred.isNotEmpty) {
          headers['Authorization'] = cred;
        }
      case 'simpleLogin':
        final cookie = r.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
      case 'uiLogin':
        // Pages take the token as a query param, mirroring
        // fetchOfflinePageBytes.
        final token = r.accessToken;
        if (token != null && token.isNotEmpty) {
          final sep = fetchUrl.contains('?') ? '&' : '?';
          fetchUrl = '$fetchUrl${sep}token=${Uri.encodeQueryComponent(token)}';
        }
    }
    final http.Response res;
    try {
      res = await backgroundHttpClient
          .get(Uri.parse(fetchUrl), headers: headers)
          .timeout(_httpTimeout);
    } on SocketException catch (e) {
      throw PageOfflineException('SocketException: $e');
    } on TimeoutException {
      throw PageOfflineException('timed out after $_httpTimeout on page fetch');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const PageAuthException();
    }
    if (isGatewayStatus(res.statusCode)) {
      throw PageOfflineException('HTTP ${res.statusCode} on page fetch');
    }
    if (res.statusCode != 200) {
      throw Exception('page fetch failed ($pageUrl): ${res.statusCode}');
    }
    return (
      bytes: res.bodyBytes,
      ext: pageImageExt(res.headers['content-type'], res.bodyBytes),
    );
  },
  refreshAuth: () async {
    if (record().authType != 'uiLogin') return false;
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    return newAccess != null;
  },
);
