// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/desktop/linux_button_layout.dart';

const double _linuxWindowCornerRadius = 15;

class LinuxWindowFrame extends StatefulWidget {
  const LinuxWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<LinuxWindowFrame> createState() => _LinuxWindowFrameState();
}

class _LinuxWindowFrameState extends State<LinuxWindowFrame> {
  static const _channel = MethodChannel('tsumiru/linux_window_frame');
  bool _rounded = true;
  bool _outlined = true;

  @override
  void initState() {
    super.initState();
    // GDK reports quick-tiling as well as maximised and fullscreen transitions.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged') {
        _updateState(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    _channel.invokeMapMethod<Object?, Object?>('getState').then((state) {
      if (state != null) _updateState(state);
    }).catchError((Object _) {});
  }

  void _updateState(Map<Object?, Object?> state) {
    linuxButtonLayoutNotifier.value =
        parseLinuxButtonLayout(state['decorationLayout']);
    if (!mounted) return;
    setState(() {
      _rounded = state['rounded'] == true;
      _outlined = state['outlined'] == true;
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = _rounded ? BorderRadius.circular(_linuxWindowCornerRadius) : BorderRadius.zero;
    final outlineColor = theme.colorScheme.onSurface.withValues(alpha: .07);
    final border = Border.all(
      color: _rounded
          ? _outlined
              ? Color.alphaBlend(outlineColor, theme.colorScheme.surface)
              : theme.colorScheme.surface
          : outlineColor,
      width: _rounded ? 2 : 1,
      strokeAlign: _rounded ? BorderSide.strokeAlignCenter : BorderSide.strokeAlignInside,
    );
    return Container(
      foregroundDecoration: BoxDecoration(borderRadius: borderRadius, border: _rounded || _outlined ? border : null),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: ColoredBox(
          color: theme.colorScheme.surface,
          child: widget.child,
        ),
      ),
    );
  }
}
