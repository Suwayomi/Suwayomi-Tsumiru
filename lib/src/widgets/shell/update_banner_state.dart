// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/manga_book/data/updates/updates_repository.dart';

part 'update_banner_state.g.dart';

/// Arm immediately on request; release after the real run ends or the safety timeout expires.
@Riverpod(keepAlive: true)
class UpdateOptimistic extends _$UpdateOptimistic {
  Timer? _safety;
  bool _sawRealRunning = false;

  @override
  bool build() {
    ref.onDispose(() => _safety?.cancel());
    return false;
  }

  void arm() {
    // Seed current running state: a second arm mid-run must still release on the next idle edge.
    _sawRealRunning = ref.read(updateRunningSocketProvider).value ?? false;
    _safety?.cancel();
    _safety = Timer(const Duration(seconds: 12), _clear);
    state = true;
  }

  void onRealRunning(bool running) {
    if (!state) return;
    if (running) {
      _sawRealRunning = true;
    } else if (_sawRealRunning) {
      _clear();
    }
  }

  void _clear() {
    _safety?.cancel();
    _sawRealRunning = false;
    state = false;
  }
}

/// Published visibility lets the shell omit the status-bar inset already occupied by the banner.
@Riverpod(keepAlive: true)
class UpdateBannerVisible extends _$UpdateBannerVisible {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
