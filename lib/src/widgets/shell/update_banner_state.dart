// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/manga_book/data/updates/updates_repository.dart';

part 'update_banner_state.g.dart';

/// Optimistic "an update was just requested" flag.
///
/// A user-triggered update (pull-to-refresh, the overflow menu, the Updates
/// FAB) takes ~1.5s before the server reports it as running, and the banner
/// then adds its own 1s appear-debounce on top — so without this the banner
/// sat blank for a couple of seconds after a pull and the action felt dead.
///
/// Callers [arm] this the instant they fire an update, which shows the banner
/// immediately (bypassing the debounce). It then hands back to the real
/// running signal: [onRealRunning] releases the optimistic hold once the
/// genuine run has been seen to start and then end, and a safety timeout
/// releases it for updates that never register as running (nothing to check /
/// failed to start).
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
    // Seed from the current run state: if an update is ALREADY running (a
    // second pull mid-run), treat it as already-seen so the next idle edge
    // releases the hold — otherwise the change-only running stream never
    // re-delivers `true` and only the safety timeout would clear it.
    _sawRealRunning = ref.read(updateRunningSocketProvider).value ?? false;
    _safety?.cancel();
    _safety = Timer(const Duration(seconds: 12), _clear);
    state = true;
  }

  /// Feed the real server running state so the optimistic hold releases once
  /// the genuine run has started and then ended.
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

/// Whether the update banner is currently on screen. Published by the banner,
/// read by the app shell to drop the now-redundant status-bar inset on the
/// content below — the banner occupies that space while it's shown, and
/// without this the pushed-down screen's own app bar reserves the status-bar
/// strip a second time, leaving a dead gap under the banner.
@Riverpod(keepAlive: true)
class UpdateBannerVisible extends _$UpdateBannerVisible {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
