// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const double kDesktopTitleBarHeight = 40;

/// Slim, seamless, theme-reactive window title bar. Windows/Linux draw our own
/// min/max/close on the right; macOS keeps the native traffic lights (left) and
/// this is just a draggable strip.
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: kDesktopTitleBarHeight,
      color: scheme.surface,
      child: Stack(
        children: [
          // The whole strip is a drag handle.
          const Positioned.fill(
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          // App name — centred and muted: present, not a banner. IgnorePointer
          // so it doesn't block the drag region beneath it.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                // Brand name (not localized). Kept as a literal so the bar never
                // depends on Localizations being in scope at the app-builder
                // level, where AppLocalizations.of() isn't reliably available.
                child: Text(
                  'Tsumiru',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          // Window controls, pinned right (Windows/Linux); macOS keeps its
          // native traffic lights on the left, so nothing is drawn there.
          if (!Platform.isMacOS)
            Align(
              alignment: Alignment.centerRight,
              child: _WindowButtons(brightness: theme.brightness),
            ),
        ],
      ),
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons({required this.brightness});
  final Brightness brightness;
  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;
    return Row(
      // Shrink-wrap the buttons so the enclosing Align can pin the cluster to
      // the right; a default (max-width) Row would left-align them.
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: b,
          onPressed: () => windowManager.minimize(),
        ),
        if (_maximized)
          WindowCaptionButton.unmaximize(
            brightness: b,
            onPressed: () => windowManager.unmaximize(),
          )
        else
          WindowCaptionButton.maximize(
            brightness: b,
            onPressed: () => windowManager.maximize(),
          ),
        WindowCaptionButton.close(
          brightness: b,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}
