// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Cancellation-aware concurrency primitives for the bulk migration runner.
/// Pure Dart, no Flutter/GraphQL — unit-testable in isolation.
library;

import 'dart:async';
import 'dart:collection';

/// Thrown when a wait is abandoned because its [CancelToken] fired.
class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'CancelledException';
}

/// A one-shot cancellation signal shared across a batch. Cancelling completes
/// [whenCancelled] so any primitive blocked on it wakes immediately.
class CancelToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Throws [CancelledException] if already cancelled — call at the top of a
  /// cancellable step.
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}

/// A counting semaphore bounding how many units of work run at once. Waiters are
/// served FIFO. A blocked [acquire] wakes and throws [CancelledException] if its
/// token fires, and is removed from the queue so it never later steals a permit.
class Semaphore {
  Semaphore(this._permits) : assert(_permits > 0);

  int _permits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get availablePermits => _permits;
  int get queueLength => _waiters.length;

  Future<void> acquire([CancelToken? token]) async {
    token?.throwIfCancelled();
    if (_permits > 0) {
      _permits--;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    if (token == null) {
      await waiter.future;
      return;
    }
    await Future.any([waiter.future, token.whenCancelled]);
    if (token.isCancelled && !waiter.isCompleted) {
      // Cancelled before a permit was handed to us: drop from the queue so a
      // later release doesn't grant a permit no one will release.
      _waiters.remove(waiter);
      throw const CancelledException();
    }
    // Otherwise a release completed our waiter and already spent a permit on us.
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _permits++;
    }
  }

  /// Runs [action] holding one permit, releasing it even on error/cancel.
  Future<T> withPermit<T>(Future<T> Function() action,
      [CancelToken? token]) async {
    await acquire(token);
    try {
      return await action();
    } finally {
      release();
    }
  }
}

/// Serializes and paces requests to at most one per [minInterval], so a large
/// batch can't hammer a source (Cloudflare / 429). Acquisitions are chained so
/// the spacing holds even under concurrent callers. Cancellation-aware: a
/// pending wait throws [CancelledException] rather than blocking the batch.
class RateLimiter {
  RateLimiter({required this.minInterval});

  final Duration minInterval;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastGranted;

  /// Reserve the next slot. Callers should await this immediately before the
  /// request and hold nothing else that could deadlock behind it.
  Future<void> acquire([CancelToken? token]) {
    token?.throwIfCancelled();
    final prior = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return prior.then((_) async {
      try {
        final now = DateTime.now();
        final earliest = _lastGranted == null
            ? now
            : _lastGranted!.add(minInterval);
        if (earliest.isAfter(now)) {
          final wait = earliest.difference(now);
          if (token == null) {
            await Future<void>.delayed(wait);
          } else {
            await Future.any([Future<void>.delayed(wait), token.whenCancelled]);
            token.throwIfCancelled();
          }
        } else {
          token?.throwIfCancelled();
        }
        _lastGranted = DateTime.now();
      } finally {
        // Release the chain so the next caller proceeds regardless of our
        // outcome — a cancelled acquire must not stall the queue forever.
        completer.complete();
      }
    });
  }
}
