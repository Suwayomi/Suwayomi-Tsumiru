// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_scroll_controller.g.dart';

/// Whether hands-free auto-scroll is currently running in the reader.
///
/// Session-scoped (autoDispose): resets to off each time the reader is
/// opened. Flipped by the keyboard trigger and the on-screen utils bar;
/// watched by the reader-mode ticker to drive the scroll loop.
@riverpod
class AutoScrollActive extends _$AutoScrollActive {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void start() => state = true;

  void stop() => state = false;
}
