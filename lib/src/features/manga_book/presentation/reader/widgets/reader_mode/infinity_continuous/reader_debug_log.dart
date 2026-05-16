// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-memory ring buffer for reader scroll/layout events. Used to
/// diagnose the "reader bumps you backward several pages mid-chapter"
/// bug. Not shipped in the main release — only on `debug/reader-*`
/// branches.
///
/// Usage:
///   ReaderDebugLog.log('event_name', {'key': 'value', ...});
///   ReaderDebugLog.mark('USER_PRESSED_BUMP');
///   final text = ReaderDebugLog.flushToClipboard();
class ReaderDebugLog {
  ReaderDebugLog._();

  /// Capacity. Older entries get evicted; the tail (most recent) is
  /// what matters for diagnosing a bump the user just felt.
  static const int _capacity = 2000;

  static final List<_Entry> _entries = [];
  static int _seq = 0;

  /// Append a structured event with arbitrary key-value attrs.
  static void log(String event, [Map<String, Object?>? attrs]) {
    final entry = _Entry(
      seq: _seq++,
      timestamp: DateTime.now(),
      event: event,
      attrs: attrs ?? const {},
    );
    _entries.add(entry);
    if (_entries.length > _capacity) {
      _entries.removeRange(0, _entries.length - _capacity);
    }
    if (kDebugMode) {
      debugPrint('[reader-dbg] $entry');
    }
  }

  /// Insert a user-pressed marker so we know which slice of the log
  /// to inspect. Time-sorted between regular events.
  static void mark(String label) {
    log('USER_MARK', {'label': label});
  }

  /// Copy the entire log to the clipboard as text and return the text.
  static Future<String> flushToClipboard() async {
    final buf = StringBuffer();
    buf.writeln('=== reader_debug_log ===');
    buf.writeln('entries=${_entries.length} (capacity=$_capacity)');
    buf.writeln('captured_at=${DateTime.now().toIso8601String()}');
    buf.writeln('');
    for (final e in _entries) {
      buf.writeln(e.toString());
    }
    final text = buf.toString();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  /// Wipe the buffer. Useful at session start.
  static void clear() {
    _entries.clear();
    _seq = 0;
  }
}

class _Entry {
  _Entry({
    required this.seq,
    required this.timestamp,
    required this.event,
    required this.attrs,
  });

  final int seq;
  final DateTime timestamp;
  final String event;
  final Map<String, Object?> attrs;

  @override
  String toString() {
    final ts = timestamp.toIso8601String();
    if (attrs.isEmpty) return '#$seq $ts $event';
    return '#$seq $ts $event ${attrs.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
  }
}
