// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_reachability.g.dart';

/// Whether the last server request failed to connect — a wrong URL, a server
/// that's down, or no network — as opposed to reaching a server that answered.
///
/// Set by the offline-fallback read path: `true` when a fetch hits a connection
/// error (even when cached data is then served, which would otherwise hide the
/// outage from the UI), `false` on any successful fetch. Watched by
/// `ServerUnreachableBannerHost` to surface an app-wide banner, so a user
/// browsing stale cached data still knows they're offline.
@Riverpod(keepAlive: true)
class ServerUnreachable extends _$ServerUnreachable {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
