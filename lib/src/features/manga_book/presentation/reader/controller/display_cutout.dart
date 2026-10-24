// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android cutout layout requires a native channel; SystemChrome cannot set it.
const MethodChannel _channel = MethodChannel('tsumiru/display_cutout');

Future<void> setDrawUnderCutout(bool enable) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<void>('setDrawUnderCutout', {'enable': enable});
  } catch (_) {
    // No channel (pre-P) or no attached activity — leave the window as-is.
  }
}
