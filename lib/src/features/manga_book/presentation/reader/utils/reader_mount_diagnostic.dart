// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../utils/crash/diagnostics.dart';

/// Logs a reader engine's mount and dispose.
///
/// The engines keep the chapter being read and the page reached in their own
/// state, so a remount silently restarts at [routeChapterId]. A dispose
/// followed by a mount without the reader having been left is that jump; the
/// dispose line records where the reader was before it.
void useReaderMountDiagnostic({
  required String engine,
  required int routeChapterId,
  required int initialPage,
  required int visibleChapterId,
  required int page,
}) {
  final position = useRef((chapterId: visibleChapterId, page: page));
  position.value = (chapterId: visibleChapterId, page: page);
  useEffect(() {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] reader: mount engine=$engine '
      'chapterId=$routeChapterId page=$initialPage\n',
    );
    return () => recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] reader: dispose engine=$engine '
      'routeChapterId=$routeChapterId '
      'chapterId=${position.value.chapterId} page=${position.value.page}\n',
    );
  }, const []);
}
