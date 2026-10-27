// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/graphql/legacy_user_fields_link.dart';
import '../../../../utils/network/gateway_status.dart';
import '../../../../utils/network/graphql_errors.dart';
import '../../../account/data/account_permission.dart';
import '../../../account/data/graphql/__generated__/account.graphql.dart';
import '../../../account/domain/account_access.dart';
import '../chapter_download_engine.dart';
import '../offline_download_providers.dart' show pageImageExt;
import '../offline_page_store.dart';
import '../offline_server_identity.dart';
import 'background_token_record.dart';

// Reuse connections for the isolate lifetime instead of TLS setup per page.
final http.Client backgroundHttpClient = http.Client();

// Bound requests so a hung proxy cannot hold .bg_lock and block foreground ownership forever.
const _httpTimeout = Duration(seconds: 30);

class BackgroundServerTarget {
  const BackgroundServerTarget({
    required this.serverBase,
    required this.port,
    required this.addPort,
    this.client,
    this.isCancelled,
    this.onNetworkError,
  });
  final String serverBase;
  final int? port;
  final bool addPort;
  final http.Client? client;
  final bool Function()? isCancelled;
  final void Function(String)? onNetworkError;

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

const Object gqlAuthError = Object();

/// Transient outage; park rather than fail the chapter.
const Object gqlNetworkError = Object();

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
  applyIsolateCustomHeaders(headers, record.extraHeaders);
}

Future<Object?> postBackgroundGraphql({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord record,
  required String query,
  required Map<String, Object?> variables,
  String? accessToken,
  bool accountCapability = false,
}) async {
  if (target.isCancelled?.call() ?? false) return gqlNetworkError;
  return postWithLegacyUserFields(
    endpoint: target.graphql,
    query: query,
    variables: variables,
    post: (query, variables, probe) => _postBackgroundGraphql(
      target: target,
      record: record,
      query: query,
      variables: variables,
      accessToken: accessToken,
      accountCapability: !probe && accountCapability,
    ),
  );
}

Future<Object?> _postBackgroundGraphql({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord record,
  required String query,
  required Map<String, Object?> variables,
  String? accessToken,
  bool accountCapability = false,
}) async {
  if (target.isCancelled?.call() ?? false) return gqlNetworkError;
  final headers = <String, String>{'Content-Type': 'application/json'};
  applyBackgroundAuthHeaders(headers, record, accessToken: accessToken);
  try {
    final res = await (target.client ?? backgroundHttpClient)
        .post(
          Uri.parse(target.graphql),
          headers: headers,
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(_httpTimeout);
    if (target.isCancelled?.call() ?? false) return gqlNetworkError;
    if (res.statusCode == 401) return gqlAuthError;
    if (res.statusCode == 403) {
      throw const AccountPermissionDenied(
        Enum$UserPermission.DOWNLOAD_CHAPTERS,
      );
    }
    // Gateway failures represent an unreachable origin, not chapter rejection.
    if (isGatewayStatus(res.statusCode)) {
      target.onNetworkError?.call('HTTP ${res.statusCode} on GraphQL request');
      return gqlNetworkError;
    }
    final decoded = jsonDecode(res.body) as Map<String, Object?>;
    final errors = (decoded['errors'] as List? ?? const []).map((value) {
      final error = (value as Map).cast<String, dynamic>();
      return GraphQLError(
        message: error['message'] as String,
        extensions: (error['extensions'] as Map?)?.cast<String, dynamic>(),
      );
    }).toList();
    final exception = errors.isEmpty
        ? null
        : OperationException(graphqlErrors: errors);
    if (accountCapability) {
      final capability = classifyAccountResponse(
        QueryResult<Query$AccountCapability>(
          options: Options$Query$AccountCapability(),
          source: QueryResultSource.network,
          data: (decoded['data'] as Map?)?.cast<String, dynamic>(),
          exception: exception,
        ),
      );
      if (capability != AccountCapability.unknown) return capability;
    }
    if (exception != null) {
      if (isPermissionDenied(exception)) {
        throw const AccountPermissionDenied(
          Enum$UserPermission.DOWNLOAD_CHAPTERS,
        );
      }
      if (isGraphqlAuthError(decoded['errors'])) {
        return gqlAuthError;
      }
      return exception;
    }
    if (res.statusCode != 200) return null;
    return decoded['data'];
  } on AccountPermissionDenied {
    rethrow;
  } on SocketException catch (error) {
    target.onNetworkError?.call('SocketException: $error');
    return gqlNetworkError;
  } on TimeoutException {
    target.onNetworkError?.call('GraphQL request timed out');
    return gqlNetworkError;
  } catch (_) {
    return null;
  }
}

Future<bool> verifyBackgroundDownloadAccess({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
}) async {
  if (target.isCancelled?.call() ?? false) return false;
  if (record().authType != 'uiLogin') return true;
  Future<Object?> read(String query, {bool capability = false}) async {
    Future<Object?> post(String? token) => postBackgroundGraphql(
      target: target,
      record: record(),
      query: query,
      variables: const {},
      accessToken: token,
      accountCapability: capability,
    );
    var result = await post(null);
    if (target.isCancelled?.call() ?? false) return null;
    if (result == gqlAuthError) {
      final fresh = await broker.resolveAfter401(record().accessToken ?? '');
      if (fresh != null) result = await post(fresh);
    }
    return (target.isCancelled?.call() ?? false) ? null : result;
  }

  final capability = await read(
    'query AccountCapability { user { id } }',
    capability: true,
  );
  if (capability == AccountCapability.unsupported) return true;
  if (capability != AccountCapability.supported) return false;
  final result = await read(
    'query DownloadAccount { user { id username roles permissions __typename } }',
  );
  if (result is! Map || result['user'] is! Map) return false;
  final Fragment$AccountDto user;
  try {
    user = Fragment$AccountDto.fromJson(
      (result['user'] as Map).cast<String, dynamic>(),
    );
  } catch (_) {
    return false;
  }
  if (user.id <= 0 || user.username.isEmpty) return false;
  if (!AccountAccess(
    capability: AccountCapability.supported,
    user: user,
  ).allows(Enum$UserPermission.DOWNLOAD_CHAPTERS)) {
    throw const AccountPermissionDenied(Enum$UserPermission.DOWNLOAD_CHAPTERS);
  }
  return true;
}

/// Empty on terminal no-pages failure; null on outage or unresolved auth. Retries 401 once.
Future<List<String>?> resolveChapterPageUrls({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  required int chapterId,
}) async {
  if (!await verifyBackgroundDownloadAccess(
    target: target,
    record: record,
    broker: broker,
  )) {
    return null;
  }
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
  if (target.isCancelled?.call() ?? false) return null;
  if (result == gqlAuthError && record().authType == 'uiLogin') {
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    if (newAccess != null) {
      result = await post(newAccess);
    } else if (broker.lastRefreshTransient) {
      return null;
    }
  }
  if (result == gqlNetworkError || result == gqlAuthError) return null;
  if (result is OperationException) throw OperationMessageException(result);
  if (result is Map<String, Object?>) {
    final chapter = result['fetchChapterPages'];
    if (chapter == null) {
      throw OperationMessageException(OperationException(graphqlErrors: []));
    }
    final pages = chapter is Map ? chapter['pages'] : null;
    if (pages is List && pages.every((page) => page is String)) {
      return pages.cast<String>();
    }
  }
  return null;
}

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
    if (target.isCancelled?.call() ?? false) {
      throw StateError('Download cancelled');
    }
    final current = record();
    final ahead = await broker.refreshIfDue(current);
    final r = ahead.sameIdentity(current) ? ahead : current;
    final fetchUrl = '${target.pageBase}$pageUrl';
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
        final token = r.accessToken;
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
    }
    applyIsolateCustomHeaders(headers, r.extraHeaders);
    final http.Response res;
    try {
      res = await (target.client ?? backgroundHttpClient)
          .get(Uri.parse(fetchUrl), headers: headers)
          .timeout(_httpTimeout);
    } on http.ClientException catch (e) {
      throw PageOfflineException('ClientException: $e');
    } on SocketException catch (e) {
      throw PageOfflineException('SocketException: $e');
    } on TimeoutException {
      throw PageOfflineException('timed out after $_httpTimeout on page fetch');
    }
    if (res.statusCode == 401) throw const PageAuthException();
    if (res.statusCode == 403) {
      throw const AccountPermissionDenied(
        Enum$UserPermission.DOWNLOAD_CHAPTERS,
      );
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
    if (target.isCancelled?.call() ?? false) return false;
    if (record().authType != 'uiLogin') return false;
    final newAccess = await broker.resolveAfter401(record().accessToken ?? '');
    return newAccess != null;
  },
);

Future<bool> verifyBackgroundServerIdentity({
  required BackgroundServerTarget target,
  required BackgroundTokenRecord Function() record,
  required TokenBroker broker,
  required String expected,
}) async {
  Future<Object?> read(String? accessToken) => postBackgroundGraphql(
    target: target,
    record: record(),
    query:
        r'query OfflineServerIdentity($key: String!) { metas(condition: {key: $key}, first: 1) { nodes { value } } }',
    variables: {'key': kTsumiruServerIdMetaKey},
    accessToken: accessToken,
  );
  try {
    var result = await read(null);
    if (target.isCancelled?.call() ?? false) return false;
    if (result == gqlAuthError && record().authType == 'uiLogin') {
      final access = await broker.resolveAfter401(record().accessToken ?? '');
      if (access != null) result = await read(access);
    }
    if (result is! Map) return false;
    final nodes = (result['metas'] as Map?)?['nodes'];
    return nodes is List &&
        nodes.isNotEmpty &&
        (nodes.first as Map)['value'] == expected;
  } on AccountPermissionDenied {
    return false;
  }
}
