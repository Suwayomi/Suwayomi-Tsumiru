// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/platform/platform_runtime.dart';

class MacOSAppUpdater {
  MacOSAppUpdater({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tsumiru/sparkle_updater');

  final MethodChannel _channel;
  bool _available = false;

  bool get isAvailable => _available;

  Future<bool> initialize() async {
    if (!isMacOSRuntime) {
      _available = false;
      return false;
    }
    try {
      _available = await _channel.invokeMethod<bool>('initialize') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
    return _available;
  }

  Future<bool> checkForUpdates() async {
    if (!_available) return false;
    try {
      final handled =
          await _channel.invokeMethod<bool>('checkForUpdates') ?? false;
      if (!handled) _available = false;
      return handled;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      _available = false;
      return false;
    }
  }
}

final macOSAppUpdaterProvider = Provider<MacOSAppUpdater>(
  (ref) => MacOSAppUpdater(),
);
