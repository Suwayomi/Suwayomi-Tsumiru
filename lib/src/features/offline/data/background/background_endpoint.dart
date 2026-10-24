// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../../../../utils/crash/diagnostics.dart';

/// Prefers reachable LAN, then external; falls back to [active] without both addresses.
/// Transport selection must not change the verified server identity.
Future<String> pickBackgroundServerBase({
  required String active,
  required String? lanUrl,
  required String? externalUrl,
  required String source,
  Future<bool> Function(String url)? isReachable,
}) async {
  if (lanUrl == null || lanUrl.isEmpty) return active;
  if (externalUrl == null || externalUrl.isEmpty) return active;
  final probe = isReachable ?? backgroundServerIsReachable;
  final watch = Stopwatch()..start();
  final lanUp = await probe(lanUrl);
  final selected = lanUp ? lanUrl : externalUrl;
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] endpoint: trigger=$source '
    'lan=${lanUp ? 'reachable' : 'unreachable'} '
    'probeMs=${watch.elapsedMilliseconds} '
    'selected=${lanUp ? 'lan' : 'external'}'
    '${selected == active ? '' : ' differs-from-foreground'}\n',
  );
  return selected;
}

/// Uses [next] for verification and its auth refresh; retains it only on success.
Future<bool> switchServerBaseIfVerified({
  required String Function() base,
  required void Function(String) setBase,
  required String next,
  required Future<bool> Function() verify,
}) async {
  final previous = base();
  setBase(next);
  var verified = false;
  try {
    verified = await verify();
  } finally {
    if (!verified) setBase(previous);
  }
  return verified;
}

/// Any response proves reachability, including auth challenges; never sends credentials.
Future<bool> backgroundServerIsReachable(
  String url, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    await httpClient
        .head(Uri.parse(Endpoints.baseApi(baseUrl: url, appendApiToUrl: false)))
        .timeout(const Duration(seconds: 2));
    return true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) httpClient.close();
  }
}
