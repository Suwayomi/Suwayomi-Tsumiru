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
/// the last buffered page was silently lost. `onPause` covers mobile
/// backgrounding; `onExitRequested` covers a desktop window-close and fires
/// while the tree is still mounted, so [flush] can safely use `ref`. On exit we
/// await the write (bounded, so a slow server can't wedge the close) so the
/// position reaches the server before the window goes away.
void useFlushProgressOnAppLifecycle(Future<void> Function() flush) {
  final flushRef = useRef(flush);
  flushRef.value = flush;
  useEffect(() {
    final listener = AppLifecycleListener(
      // onPause: mobile background. onHide: web tab-hide/close and desktop
      // minimize (web never reaches `paused` on a tab-hide, so onPause alone
      // would miss it).
      onPause: () => unawaited(flushRef.value()),
      onHide: () => unawaited(flushRef.value()),
      onExitRequested: () async {
        await flushRef.value().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
        return AppExitResponse.exit;
      },
    );
    return listener.dispose;
  }, const []);
}
