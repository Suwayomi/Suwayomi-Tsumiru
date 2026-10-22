// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebSelectionArea extends StatelessWidget {
  const WebSelectionArea({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !enabled) return child;
    if (SelectionContainer.maybeOf(context) != null) return child;
    return SelectionArea(child: child);
  }
}
