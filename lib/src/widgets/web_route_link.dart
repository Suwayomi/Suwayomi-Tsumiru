// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';

class WebRouteLink extends StatelessWidget {
  const WebRouteLink({
    super.key,
    required this.location,
    required this.builder,
    this.enabled = true,
  });

  final String? location;
  final Widget Function(BuildContext context, VoidCallback? openInNewTab)
  builder;
  final bool enabled;

  static bool _isNewTabClick() {
    final keys = HardwareKeyboard.instance;
    return keys.isControlPressed || keys.isMetaPressed;
  }

  static void handleTap(VoidCallback? openInNewTab, VoidCallback onTap) {
    if (openInNewTab != null && _isNewTabClick()) {
      openInNewTab();
    } else {
      onTap();
    }
  }

  static void handleAsyncTap(VoidCallback? openInNewTab, AsyncCallback onTap) {
    if (openInNewTab != null && _isNewTabClick()) {
      openInNewTab();
    } else {
      unawaited(onTap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = this.location;
    if (!kIsWeb || !enabled || location == null) {
      return builder(context, null);
    }
    return SelectionContainer.disabled(
      child: Link(
        uri: Uri.base.replace(fragment: location),
        target: LinkTarget.blank,
        builder: (context, followLink) => builder(context, followLink),
      ),
    );
  }
}
