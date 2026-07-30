// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Mutual exclusion between the completion log's writers (foreground-service
/// worker, background catch-up executor) and its consumer (replay, which also
/// truncates). Heartbeat-based: staleness is judged by heartbeat age, never
/// acquisition age — an FGS run is legitimately unbounded, and the WorkManager
/// isolate shares the app process, so pid liveness distinguishes nothing.
class BackgroundDownloadLock {
  BackgroundDownloadLock(this.file);
  final File file;

  static const heartbeatEvery = Duration(seconds: 5);

  /// A holder whose heartbeat is older than this is dead — generous vs the
  /// 5-second renewal so one missed beat (GC pause, IO stall) can't lose a
  /// live lock.
  static const staleAfter = Duration(seconds: 45);

  Timer? _beat;
  String? _held;

  /// Try to take the lock as [holder]. Returns false while another live holder
  /// has it; a stale holder's lock is replaced.
  Future<bool> acquire(String holder) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = await _read();
    if (current != null &&
        current['holder'] != holder &&
        now - ((current['beat'] as num?)?.toInt() ?? 0) <
            staleAfter.inMilliseconds) {
      return false;
    }
    _held = holder;
    await _write({'holder': holder, 'beat': now, 'yield': false});
    _beat = Timer.periodic(heartbeatEvery, (_) => _renew());
    return true;
  }

  Future<void> _renew() async {
    final holder = _held;
    if (holder == null) return;
    final current = await _read();
    // Renew only our own record — a steal after a false-stale call must win.
    if (current == null || current['holder'] != holder) return;
    await _write({
      'holder': holder,
      'beat': DateTime.now().millisecondsSinceEpoch,
      'yield': current['yield'] == true,
    });
  }

  /// Ask the current holder to stop at its next checkpoint. Used by replay at
  /// app launch so it never waits out a multi-minute worker run.
  Future<void> requestYield() async {
    final current = await _read();
    if (current == null) return;
    await _write({...current, 'yield': true});
  }

  /// The holder polls this between chapters/pages and stops cleanly when set.
  Future<bool> yieldRequested() async {
    final current = await _read();
    return current?['yield'] == true;
  }

  Future<void> release() async {
    _beat?.cancel();
    _beat = null;
    _held = null;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A failed delete just leaves a record that goes stale in [staleAfter].
    }
  }

  Future<Map<String, Object?>?> _read() async {
    try {
      if (!await file.exists()) return null;
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return null; // torn write — treat as absent
    }
  }

  Future<void> _write(Map<String, Object?> record) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(record), flush: true);
  }
}
