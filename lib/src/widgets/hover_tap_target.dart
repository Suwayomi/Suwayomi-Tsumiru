// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Mouse-only hover/cursor wrapper; touch does not trigger hovered.
class HoverTapTarget extends StatefulWidget {
  const HoverTapTarget({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverTapTarget> createState() => _HoverTapTargetState();
}

class _HoverTapTargetState extends State<HoverTapTarget> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Builder(builder: (context) => widget.builder(context, _hovered)),
  );
}
