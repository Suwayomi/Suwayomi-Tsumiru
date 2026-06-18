// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';

/// TEMPORARY scroll diagnostics for the back-scroll-snap investigation.
/// Logs large/programmatic scroll events to an in-memory ring buffer that the
/// reader's "COPY LOG" button dumps to the clipboard. Remove once the bug is
/// fixed.
class ReaderScrollDiag {
  ReaderScrollDiag._();

  static final List<String> _log = [];

  static void add(String event) {
    final now = DateTime.now().toIso8601String();
    _log.add('${now.substring(11, 23)}  $event');
    if (_log.length > 500) _log.removeAt(0);
  }

  static Future<void> copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
  }

  static void clear() => _log.clear();
}
