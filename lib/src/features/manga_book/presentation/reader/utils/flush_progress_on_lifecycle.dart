// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Flushes the reader's pending (debounced) progress on app background and on
/// exit.
///
/// The reader otherwise only flushes on a Flutter route-pop or widget dispose.
/// Neither fires when a desktop window is closed straight from the reader, so
/// the last buffered page was silently lost. `onHide` covers web tab-hide/close,
/// desktop minimize, and mobile background (the `hidden` state precedes
/// `paused`, so onPause would only double-fire). `onExitRequested` covers a
/// desktop window-close; it fires while the tree is still mounted, so [flush]
/// can safely use `ref`. Both go through [flush], which is bounded and swallows
/// errors so a slow or failing write can neither wedge nor abort the close.
void useFlushProgressOnAppLifecycle(Future<void> Function() flush) {
  final flushRef = useRef(flush);
  flushRef.value = flush;
  useEffect(() {
    // A failed/slow write must not surface as an unhandled async error on
    // background, nor abort the window close by erroring out of onExitRequested.
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
