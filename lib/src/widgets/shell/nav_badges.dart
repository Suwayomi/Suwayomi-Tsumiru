// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../constants/navigation_bar_data.dart';

Widget badgedNavIcon(
  Widget icon,
  NavigationBarData data,
  bool downloadsPaused,
  int extensionUpdates,
) {
  if (data.icon == FluentIcons.arrow_download_24_regular && downloadsPaused) {
    return Badge(child: icon);
  }
  if (data.icon == FluentIcons.compass_northwest_24_regular && extensionUpdates > 0) {
    return Badge(label: Text('$extensionUpdates'), child: icon);
  }
  return icon;
}
