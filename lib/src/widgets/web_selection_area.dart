// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_copy_handler.dart';

class WebSelectionArea extends StatefulWidget {
  const WebSelectionArea({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<WebSelectionArea> createState() => _WebSelectionAreaState();
}

class _WebSelectionAreaState extends State<WebSelectionArea> {
  String? _selectedText;
  late final void Function() _detachCopy;

  @override
  void initState() {
    super.initState();
    _detachCopy = attachWebCopyHandler(
      () => widget.enabled ? _selectedText : null,
    );
  }

  @override
  void dispose() {
    _detachCopy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !widget.enabled) return widget.child;
    if (SelectionContainer.maybeOf(context) != null) return widget.child;
    return SelectionArea(
      onSelectionChanged: (content) => _selectedText = content?.plainText,
      child: widget.child,
    );
  }
}
