// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../../../../utils/crash/diagnostics.dart';

/// Which of the server's addresses a background run should talk to.
///
/// The foreground keeps the active address on the LAN one while it answers
/// and on the external one otherwise, and re-checks on every network change.
/// A background run used to inherit whichever was active when the app last
/// ran: closed at home, every later run away from home timed out on the LAN
/// address until the app was opened again. Each run now makes the same
/// choice the foreground would, from the same two addresses: the LAN one if
/// it answers, the external one otherwise.
///
/// Only the transport changes. The run's identity checks stay tied to the
/// address the foreground verified, and the server it reaches is checked
/// against the offline catalogue (`verifyBackgroundServerIdentity`) before
/// anything is downloaded, whichever address answered.
///
/// Without both addresses (none set up, or a record from before they were
/// kept) the [active] address is used as before.
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

/// The foreground's LAN probe (`serverUrlIsReachable`), without its Riverpod
/// surroundings: any answer at all, auth challenge included, means the host
/// is there. Never sends credentials.
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
