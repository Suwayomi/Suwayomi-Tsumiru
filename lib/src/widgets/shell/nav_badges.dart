// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../constants/navigation_bar_data.dart';

Widget badgedNavIcon(
  Widget icon,
  NavigationBarData data,
  bool downloadsPaused,
  int extensionUpdates,
) {
  if (data.icon == Icons.download_outlined && downloadsPaused) {
    return Badge(child: icon);
  }
  if (data.icon == Icons.explore_outlined && extensionUpdates > 0) {
    return Badge(label: Text('$extensionUpdates'), child: icon);
  }
  return icon;
}
