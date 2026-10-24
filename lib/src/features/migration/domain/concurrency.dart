// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

import 'dart:async';
import 'dart:collection';

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'CancelledException';
}

/// One-shot cancellation wakes all primitives waiting on [whenCancelled].
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

  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}

/// FIFO semaphore; cancellation removes a blocked waiter and throws [CancelledException].
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
      // Remove cancelled waiters so a later release cannot strand a permit.
      _waiters.remove(waiter);
      throw const CancelledException();
    }
    // A completed waiter already owns a permit.
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _permits++;
    }
  }

  /// Holds one permit through completion, including errors and cancellation.
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

/// Serializes requests at [minInterval] spacing, including concurrent callers; waits are cancellable.
class RateLimiter {
  RateLimiter({required this.minInterval});

  final Duration minInterval;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastGranted;

  /// Await immediately before requesting, without holding resources that could deadlock.
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
        // Cancellation must release the chain so later callers can proceed.
        completer.complete();
      }
    });
  }
}
