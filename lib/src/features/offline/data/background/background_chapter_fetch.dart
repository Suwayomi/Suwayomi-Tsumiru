// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../chapter_download_engine.dart';
import '../offline_download_providers.dart' show pageImageExt;
import '../offline_page_store.dart';
import 'background_token_record.dart';

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
      baseUrl: serverBase, port: port, addPort: addPort, isGraphQl: true);

  String get pageBase => Endpoints.baseApi(
      baseUrl: serverBase, port: port, addPort: addPort, appendApiToUrl: false);
}

/// Sentinel: 401/403 — distinct from "no pages / other error" (empty list).
const Object gqlAuthError = Object();

/// Sentinel: server unreachable (transient) — the caller parks, doesn't error.
const Object gqlNetworkError = Object();

/// The app's auth modes on a hand-rolled request (uiLogin Bearer, basic,
/// simpleLogin cookie).
void applyBackgroundAuthHeaders(
    Map<String, String> headers, BackgroundTokenRecord record,
    {String? accessToken}) {
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
    final res = await http.post(Uri.parse(target.graphql),
        headers: headers, body: jsonEncode({'query': query, 'variables': variables}));
    if (res.statusCode == 401 || res.statusCode == 403) return gqlAuthError;
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body) as Map<String, Object?>;
    return decoded['data'];
  } on SocketException {
    return gqlNetworkError;
  } catch (_) {
    return null;
  }
}

/// A chapter's page URLs: the list on success, empty on terminal failure, null
/// when the server was unreachable. Retries once through the broker on 401.
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
    if (newAccess != null) result = await post(newAccess);
  }
  if (result == gqlNetworkError) return null;
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
}) =>
    ChapterDownloadEngine(
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
              fetchUrl =
                  '$fetchUrl${sep}token=${Uri.encodeQueryComponent(token)}';
            }
        }
        final http.Response res;
        try {
          res = await http.get(Uri.parse(fetchUrl), headers: headers);
        } on SocketException {
          throw const PageOfflineException();
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw const PageAuthException();
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
        final newAccess =
            await broker.resolveAfter401(record().accessToken ?? '');
        return newAccess != null;
      },
    );
