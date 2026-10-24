// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Flush on hidden/exitRequested with bounded, error-tolerant writes; window close may skip pop/dispose.
void useFlushProgressOnAppLifecycle(Future<void> Function() flush) {
  final flushRef = useRef(flush);
  flushRef.value = flush;
  useEffect(() {
    // A failed flush must neither raise an unhandled background error nor abort window close.
    Future<void> safeFlush() async {
      try {
        await flushRef.value().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    final listener = AppLifecycleListener(
      onHide: () => unawaited(safeFlush()),
      onExitRequested: () async {
        await safeFlush();
        return AppExitResponse.exit;
      },
    );
    return listener.dispose;
  }, const []);
}
