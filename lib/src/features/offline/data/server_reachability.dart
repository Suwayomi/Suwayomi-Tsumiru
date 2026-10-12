// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../utils/crash/diagnostics.dart';
import '../../../utils/crash/redact_tokens.dart';

part 'server_reachability.g.dart';

/// Whether the last server request failed to connect — a wrong URL, a server
/// that's down, or no network — as opposed to reaching a server that answered.
///
/// Set by the offline-fallback read path: `true` when a fetch hits a connection
/// error (even when cached data is then served, which would otherwise hide the
/// outage from the UI), `false` on any successful fetch. Watched by
/// `ServerUnreachableBanner`, which the library and series screens mount, so a
/// user browsing stale cached data still knows they're offline.
@Riverpod(keepAlive: true)
class ServerUnreachable extends _$ServerUnreachable {
  @override
  bool build() => false;

  /// [reason] says what flipped it, for the debug log: while it's set, the
  /// library serves the on-device catalog without trying the server, so an
  /// unexplained flip at launch looked like the library losing its counts.
  void set(bool value, {String? reason}) {
    if (state == value) return;
    state = value;
    recordDiagnostic(
      redactTokens(
        '[${DateTime.now().toIso8601String()}] reachability: '
        '${value ? 'unreachable' : 'reachable'}'
        '${reason == null ? '' : ' $reason'}\n',
      ),
    );
  }
}

/// User-requested offline view: skip the network entirely and serve the
/// on-device catalog. Set by the "View offline" button shown while a
/// fallback-capable read is still waiting on its network window, so nobody has
/// to sit out even the capped wait. Session-only by design — a restart or a
/// manual refresh goes back to trying the server first.
@Riverpod(keepAlive: true)
class ViewOfflineNow extends _$ViewOfflineNow {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
