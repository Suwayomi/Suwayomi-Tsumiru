// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

/// Native implementation: e.g. `android 15`, `linux (flatpak) 7.2.3`.
String currentPlatformDescription() {
  final env = Platform.environment;
  final package = env.containsKey('FLATPAK_ID')
      ? ' (flatpak)'
      : env.containsKey('APPIMAGE')
      ? ' (appimage)'
      : '';
  return '${Platform.operatingSystem}$package '
      '${Platform.operatingSystemVersion}';
}
