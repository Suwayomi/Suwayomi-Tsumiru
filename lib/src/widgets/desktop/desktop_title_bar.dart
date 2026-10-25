// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../constants/app_constants.dart';
import '../../utils/platform/platform_runtime.dart';
import '../tsumiru_logo.dart';

const double kDesktopTitleBarHeight = 40;

const double kBrandLogoSize = 28;
const double kBrandGap = 8;

TextStyle? brandNameStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );
}

/// Literal brand name avoids requiring Localizations above the app.
class DesktopBrandTitle extends StatelessWidget {
  const DesktopBrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TsumiruLogo(size: kBrandLogoSize),
        const SizedBox(width: kBrandGap),
        Text(kAppName, style: brandNameStyle(context)),
      ],
    );
  }
}

/// Native draggable strip: Windows/Linux get controls; macOS retains traffic lights.
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final native = isDesktopPlatform;
    return Container(
      height: kDesktopTitleBarHeight,
      color: scheme.surface,
      child: Stack(
        children: [
          if (native)
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          // IgnorePointer lets the brand remain inside the drag region.
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: DesktopBrandTitle()),
            ),
          ),
          if (native && !isMacOSRuntime)
            Align(
              alignment: Alignment.centerRight,
              child: DesktopWindowButtons(brightness: theme.brightness),
            ),
        ],
      ),
    );
  }
}

class DesktopWindowButtons extends StatefulWidget {
  const DesktopWindowButtons({super.key, required this.brightness});
  final Brightness brightness;
  @override
  State<DesktopWindowButtons> createState() => _DesktopWindowButtonsState();
}

class _DesktopWindowButtonsState extends State<DesktopWindowButtons>
    with WindowListener {
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
      // Shrink-wrap so Align can position the controls on the right.
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
