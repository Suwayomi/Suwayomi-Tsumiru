// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_scroll_controller.g.dart';

/// Session-scoped; resets to off when the reader is closed.
@riverpod
class AutoScrollActive extends _$AutoScrollActive {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void start() => state = true;

  void stop() => state = false;
}
