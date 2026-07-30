// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Mutual exclusion between the completion log's writers (foreground-service
/// worker, background catch-up executor) and its consumer (replay, which also
/// truncates).
///
/// Built on the one atomic filesystem primitive Dart offers — exclusive file
/// creation (`File.create(exclusive: true)` throws when the file exists;
/// `Directory.create` is idempotent and useless as a mutex). The holder's
/// identity is the file's content, the heartbeat is its mtime (touched, never
/// rewritten), and a yield request is a separate marker file, so no path does
/// a read-modify-write that another party could interleave. Staleness is
/// judged by heartbeat age, never acquisition age — an FGS run is legitimately
/// unbounded, and all parties share one process, so pid liveness distinguishes
/// nothing.
class BackgroundDownloadLock {
  BackgroundDownloadLock(this.lockFile);

  final File lockFile;

  File get _yieldFile => File('${lockFile.path}.yield');

  static const heartbeatEvery = Duration(seconds: 5);

  /// Generous vs the 5-second renewal so one missed beat (GC pause, IO stall)
  /// can't lose a live lock.
  static const staleAfter = Duration(seconds: 45);

  Timer? _beat;
  String? _held;

  /// Take the lock as [holder]. False while another live holder has it; a
  /// stale holder's lock is broken and re-contended (jitter + verify, so two
  /// breakers can't both win).
  Future<bool> acquire(String holder) async {
    // Unique per attempt: two same-named contenders (a restarted FGS racing
    // its predecessor's stale lock) must still be distinguishable.
    final identity = '$holder#${Random().nextInt(1 << 31)}';
    if (!await _tryCreate(identity)) {
      if (!await _isStale()) return false;
      // Break the stale lock, jitter, then contend again — if a rival broke
      // and created first, our exclusive create fails and we lose cleanly.
      try {
        await lockFile.delete();
      } catch (_) {}
      await Future<void>.delayed(
          Duration(milliseconds: 50 + Random().nextInt(200)));
      if (!await _tryCreate(identity)) return false;
    }
    // The write after the exclusive create isn't atomic with it; verify the
    // content is ours before trusting the lock.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (await _currentHolder() != identity) return false;
    _held = identity;
    try {
      await _yieldFile.delete(); // a stale request must not stop a fresh run
    } catch (_) {}
    _beat = Timer.periodic(heartbeatEvery, (_) => _renew());
    return true;
  }

  Future<bool> _tryCreate(String identity) async {
    try {
      await lockFile.parent.create(recursive: true);
      await lockFile.create(exclusive: true);
    } catch (_) {
      return false;
    }
    await lockFile.writeAsString(identity, flush: true);
    return true;
  }

  Future<String?> _currentHolder() async {
    try {
      return await lockFile.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isStale() async {
    try {
      final beat = (await lockFile.stat()).modified;
      return DateTime.now().difference(beat) > staleAfter;
    } catch (_) {
      return true; // gone already
    }
  }

  Future<void> _renew() async {
    if (_held == null) return;
    try {
      // Touch only — never rewrites content, so a steal can't be papered over
      // and a yield marker is untouched.
      await lockFile.setLastModified(DateTime.now());
    } catch (_) {
      // Stolen or wiped: stop renewing; the caller's yield checks will end it.
      _beat?.cancel();
    }
  }

  /// Ask the current holder to stop at its next checkpoint. Marker-file
  /// existence is the flag — creation is atomic and independent of renewals.
  Future<void> requestYield() async {
    try {
      await _yieldFile.parent.create(recursive: true);
      await _yieldFile.writeAsString('', flush: true);
    } catch (_) {}
  }

  /// The holder polls this between chapters/pages and stops cleanly when set.
  Future<bool> yieldRequested() => _yieldFile.exists();

  Future<void> release() async {
    _beat?.cancel();
    _beat = null;
    final identity = _held;
    _held = null;
    if (identity == null) return;
    // Only the owner may delete — a displaced holder must not take down its
    // successor's lock.
    if (await _currentHolder() != identity) return;
    try {
      await lockFile.delete();
    } catch (_) {}
  }
}
