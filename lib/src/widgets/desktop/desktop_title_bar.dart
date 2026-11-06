// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../constants/app_constants.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/desktop/linux_button_layout.dart';
import '../../utils/platform/platform_runtime.dart';
import '../tsumiru_logo.dart';

part 'desktop_window_button.dart';

const double kDesktopTitleBarHeight = 40;

const double kBrandLogoSize = 28;
const double kBrandGap = 8;
const double _linuxWindowButtonHitSize = 34;
const double _linuxWindowButtonCircleSize = 24;
const double _linuxWindowButtonGap = 3;
const double _linuxWindowButtonEndPadding = 6;
double linuxWindowButtonsWidth(int count) => count == 0
    ? 0
    : count * _linuxWindowButtonHitSize +
          (count - 1) * _linuxWindowButtonGap +
          _linuxWindowButtonEndPadding;

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
  const DesktopTitleBar({super.key, this.hideBrand = false});

  /// Hides the brand mark on routes that show their own hero logo.
  final bool hideBrand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final native = isDesktopPlatform;
    final brand = isLinuxRuntime
        ? const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DesktopBrandTitle(),
                ),
              ),
            ],
          )
        : const Center(child: DesktopBrandTitle());
    final linuxButtons = isLinuxRuntime && native;
    return ValueListenableBuilder<LinuxButtonLayout>(
      valueListenable: linuxButtonLayoutNotifier,
      builder: (context, layout, _) => Container(
        height: kDesktopTitleBarHeight,
        color: scheme.surface,
        child: Stack(
          children: [
            if (native)
              const Positioned.fill(
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
            // IgnorePointer lets the brand remain inside the drag region.
            if (hideBrand) const SizedBox.shrink() else Positioned.fill(
              left: linuxButtons
                  ? linuxWindowButtonsWidth(layout.leading.length)
                  : 0,
              right: linuxButtons
                  ? linuxWindowButtonsWidth(layout.trailing.length)
                  : 0,
              child: IgnorePointer(
                child: brand,
              ),
            ),
            if (linuxButtons && layout.leading.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: DesktopWindowButtons(
                  brightness: theme.brightness,
                  linuxButtons: layout.leading,
                  leading: true,
                ),
              ),
            if (native &&
                !isMacOSRuntime &&
                (!linuxButtons || layout.trailing.isNotEmpty))
              Align(
                alignment: Alignment.centerRight,
                child: DesktopWindowButtons(
                  brightness: theme.brightness,
                  linuxButtons: linuxButtons ? layout.trailing : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DesktopWindowButtons extends StatefulWidget {
  const DesktopWindowButtons({
    super.key,
    required this.brightness,
    this.linuxButtons,
    this.leading = false,
  });
  final Brightness brightness;

  final List<LinuxWindowButton>? linuxButtons;

  final bool leading;
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

  Widget _linuxButton(BuildContext context, LinuxWindowButton button) {
    switch (button) {
      case LinuxWindowButton.minimize:
        return _AdwaitaButton(
          glyph: _WindowGlyph.minimize,
          onPressed: () => windowManager.minimize(),
        );
      case LinuxWindowButton.maximize:
        return _AdwaitaButton(
          glyph: _maximized ? _WindowGlyph.restore : _WindowGlyph.maximize,
          onPressed: () => _maximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        );
      case LinuxWindowButton.close:
        return _AdwaitaButton(
          glyph: _WindowGlyph.close,
          label: AppLocalizations.of(context)?.close,
          onPressed: () => windowManager.close(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linuxButtons = widget.linuxButtons;
    if (linuxButtons != null) {
      return Padding(
        padding: widget.leading
            ? const EdgeInsets.only(left: _linuxWindowButtonEndPadding)
            : const EdgeInsets.only(right: _linuxWindowButtonEndPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _linuxWindowButtonGap,
          children: [
            for (final button in linuxButtons) _linuxButton(context, button),
          ],
        ),
      );
    }
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
