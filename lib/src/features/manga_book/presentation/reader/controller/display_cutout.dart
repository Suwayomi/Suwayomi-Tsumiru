// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toggles the Android window's display-cutout layout mode — SHORT_EDGES draws
/// reader content into the notch/punch-hole area, DEFAULT keeps it clear.
/// Flutter's SystemChrome can't set this attribute, so it goes through a native
/// MethodChannel (see MainActivity.kt). No-op on non-Android / older OS.
const MethodChannel _channel = MethodChannel('tsumiru/display_cutout');

Future<void> setDrawUnderCutout(bool enable) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<void>('setDrawUnderCutout', {'enable': enable});
  } catch (_) {
    // No channel (pre-P) or no attached activity — leave the window as-is.
  }
}
