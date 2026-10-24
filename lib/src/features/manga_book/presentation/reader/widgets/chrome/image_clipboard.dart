// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android image clipboard uses a FileProvider content URI without re-encoding.
const _channel = MethodChannel('tsumiru/clipboard');

bool get imageClipboardSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Puts [path]'s image on the clipboard. Returns true on success. Throws only
/// on an unexpected native failure (callers should catch and toast).
Future<bool> copyImageToClipboard(String path) async {
  if (!imageClipboardSupported) return false;
  final ok = await _channel.invokeMethod<bool>('copyImage', {'path': path});
  return ok ?? false;
}
