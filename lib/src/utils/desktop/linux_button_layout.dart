// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

enum LinuxWindowButton { minimize, maximize, close }

class LinuxButtonLayout {
  const LinuxButtonLayout({this.leading = const [], this.trailing = const []});

  final List<LinuxWindowButton> leading;
  final List<LinuxWindowButton> trailing;

  static const LinuxButtonLayout fallback = LinuxButtonLayout(
    trailing: [
      LinuxWindowButton.minimize,
      LinuxWindowButton.maximize,
      LinuxWindowButton.close,
    ],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinuxButtonLayout &&
          listEquals(leading, other.leading) &&
          listEquals(trailing, other.trailing);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(leading), Object.hashAll(trailing));
}

final ValueNotifier<LinuxButtonLayout> linuxButtonLayoutNotifier =
    ValueNotifier<LinuxButtonLayout>(LinuxButtonLayout.fallback);

LinuxButtonLayout parseLinuxButtonLayout(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return LinuxButtonLayout.fallback;
  }
  final parts = raw.split(':');
  return LinuxButtonLayout(
    leading: _parseLayoutSide(parts[0]),
    trailing: _parseLayoutSide(parts.length > 1 ? parts[1] : ''),
  );
}

List<LinuxWindowButton> _parseLayoutSide(String side) {
  final buttons = <LinuxWindowButton>[];
  for (final item in side.split(',')) {
    switch (item.trim()) {
      case 'minimize':
        buttons.add(LinuxWindowButton.minimize);
      case 'maximize':
        buttons.add(LinuxWindowButton.maximize);
      case 'close':
        buttons.add(LinuxWindowButton.close);
    }
  }
  return buttons;
}
