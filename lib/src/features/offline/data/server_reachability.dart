// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../utils/crash/diagnostics.dart';
import '../../../utils/crash/redact_tokens.dart';

part 'server_reachability.g.dart';

/// True on connection failure even when cache is served; server error responses do not imply offline.
@Riverpod(keepAlive: true)
class ServerUnreachable extends _$ServerUnreachable {
  @override
  bool build() => false;

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

/// Session-only network bypass, cleared by restart or manual refresh.
@Riverpod(keepAlive: true)
class ViewOfflineNow extends _$ViewOfflineNow {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
