// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../utils/platform/platform_runtime.dart';
import '../tsumiru_logo.dart';

const double kDesktopTitleBarHeight = 40;

/// Logo size and logo-to-name gap shared by the title bar and the merged top
/// bar, so the brand measures the same in both.
const double kBrandLogoSize = 28;
const double kBrandGap = 8;

/// The brand name style, shared by [DesktopBrandTitle] and the top-bar
/// breakpoint math so both measure the same text.
TextStyle? brandNameStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.onSurface,
  );
}

/// The brand mark: logo plus the app name. The name is a literal, not
/// localized, so the bar never depends on Localizations being in scope at the
/// app-builder level, where AppLocalizations.of() isn't reliably available.
class DesktopBrandTitle extends StatelessWidget {
  const DesktopBrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TsumiruLogo(size: kBrandLogoSize),
        const SizedBox(width: kBrandGap),
        Text('Tsumiru', style: brandNameStyle(context)),
      ],
    );
  }
}

/// Slim, seamless, theme-reactive window title bar. Windows/Linux draw our own
/// min/max/close on the right; macOS keeps the native traffic lights (left) and
/// this is just a draggable strip. Off native desktop (the merged bar's
/// two-row fallback on web/tablets) there is no window to drag or control,
/// so this is just a plain surface row.
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
          // The whole strip is a drag handle.
          if (native)
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          // Brand, centred: present, not a banner. IgnorePointer so it
          // doesn't block the drag region beneath it.
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: DesktopBrandTitle()),
            ),
          ),
          // Window controls, pinned right (Windows/Linux); macOS keeps its
          // native traffic lights on the left, so nothing is drawn there.
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

/// The minimise / maximise-restore / close cluster, shrink-wrapped so the
/// caller can pin it right. Public so the merged top bar reuses the exact
/// same buttons.
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
