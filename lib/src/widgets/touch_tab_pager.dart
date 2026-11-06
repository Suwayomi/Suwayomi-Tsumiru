// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class TouchTabPager extends StatelessWidget {
  const TouchTabPager({
    super.key,
    required this.children,
    this.controller,
  });

  final List<Widget> children;
  final TabController? controller;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: behavior.dragDevices.difference({PointerDeviceKind.mouse}),
      ),
      child: TabBarView(
        controller: controller,
        children: [
          for (final child in children)
            ScrollConfiguration(behavior: behavior, child: child),
        ],
      ),
    );
  }
}
