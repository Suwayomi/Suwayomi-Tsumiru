// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:graphql/client.dart';

import '../../../constants/enum.dart';
import '../../../utils/network/graphql_errors.dart';
import 'auth_coordinator.dart';

class SuwayomiAuthLink extends Link {
  SuwayomiAuthLink({
    required this.authType,
    required this.getHeaders,
    required this.refreshAccessToken,
    required this.onNeedsReauth,
    this.isCurrentSession,
  });

  final AuthType Function() authType;

  /// Called per request; null means no auth headers.
  final Future<Map<String, String>?> Function() getHeaders;

  /// UI Login refresh after a 401; AuthCoordinator shares one in-flight refresh across links.
  final Future<RefreshOutcome> Function() refreshAccessToken;

  final void Function() onNeedsReauth;

  final bool Function()? isCurrentSession;

  void _checkSession() {
    if (isCurrentSession?.call() == false) {
      throw StateError('Authentication session changed');
    }
  }

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    _checkSession();
    final next = forward!;
    final Map<String, String>? headers;
    try {
      headers = await getHeaders();
    } catch (error) {
      _checkSession();
      // Refresh only auth failures; disposed refs and other header errors must propagate.
      if (_isThrownAuthError(error)) {
        yield* _handle401(request, next, originalError: error);
        return;
      }
      rethrow;
    }
    _checkSession();
    final resolvedHeaders = headers;
    final withHeaders = resolvedHeaders == null
        ? request
        : request.updateContextEntry<HttpLinkHeaders>(
            (HttpLinkHeaders? entry) => HttpLinkHeaders(
              headers: <String, String>{
                ...?entry?.headers,
                ...resolvedHeaders,
              },
            ),
          );

    // Inspect the first event without using .first, which would cancel GraphQL subscriptions.
    Response? first401;
    try {
      var sawFirst = false;
      await for (final response in next(withHeaders)) {
        _checkSession();
        if (!sawFirst) {
          sawFirst = true;
          if (_is401(response)) {
            // A first-event 401 rejects the subscription, so cancel it before refreshing.
            first401 = response;
            break;
          }
        }
        yield response;
      }
    } catch (error) {
      _checkSession();
      // HttpLink throws on HTTP 401/403 instead of emitting a GraphQL error response.
      if (_isThrownAuthError(error)) {
        yield* _handle401(request, next, originalError: error);
        return;
      }
      rethrow;
    }

    if (first401 != null) {
      yield* _handle401(request, next, originalResponse: first401);
    }
  }

  // Preserve the original failure shape whether auth failed via HTTP or GraphQL.
  Stream<Response> _handle401(
    Request request,
    NextLink forward, {
    Response? originalResponse,
    Object? originalError,
  }) async* {
    _checkSession();
    if (authType() != AuthType.uiLogin) {
      _checkSession();
      onNeedsReauth();
      yield* _surfaceOriginal(originalResponse, originalError);
      return;
    }

    _checkSession();
    final outcome = await refreshAccessToken();
    _checkSession();
    switch (outcome) {
      case RefreshAuthFailure():
        _checkSession();
        onNeedsReauth();
        yield* _surfaceOriginal(originalResponse, originalError);
        return;
      case RefreshTransientFailure():
        // Transient refresh failures must not mark the session dead.
        yield* _surfaceOriginal(originalResponse, originalError);
        return;
      case RefreshSuccess(:final newAccessToken):
        // Retry once; a second auth failure marks the session dead.
        final retried = request.updateContextEntry<HttpLinkHeaders>(
          (HttpLinkHeaders? entry) => HttpLinkHeaders(
            headers: <String, String>{
              ...?entry?.headers,
              'Authorization': 'Bearer $newAccessToken',
            },
          ),
        );
        Response? retryFirst401;
        try {
          var sawRetryFirst = false;
          _checkSession();
          await for (final response in forward(retried)) {
            _checkSession();
            if (!sawRetryFirst) {
              sawRetryFirst = true;
              if (_is401(response)) {
                retryFirst401 = response;
                break;
              }
            }
            yield response;
          }
        } catch (error) {
          _checkSession();
          if (!_isThrownAuthError(error)) rethrow;
          _checkSession();
          onNeedsReauth();
          rethrow;
        }
        if (retryFirst401 != null) {
          _checkSession();
          onNeedsReauth();
          _checkSession();
          yield retryFirst401;
        }
        return;
    }
  }

  Stream<Response> _surfaceOriginal(
    Response? originalResponse,
    Object? originalError,
  ) async* {
    _checkSession();
    if (originalResponse != null) {
      yield originalResponse;
    } else {
      throw originalError!;
    }
  }

  bool _isThrownAuthError(Object error) {
    if (isSignInSessionEnded(error)) return true;
    final ex = error is OperationException ? error.linkException : error;
    return ex is HttpLinkServerException && ex.response.statusCode == 403;
  }

  bool _is401(Response response) {
    return isSignInSessionEnded(
      OperationException(graphqlErrors: response.errors ?? const []),
    );
  }
}
