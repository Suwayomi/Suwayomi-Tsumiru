import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// Scale applied to switches on the desktop shell ([ContextExtensions.usesDesktopShell]).
const double kDesktopSwitchScale = 0.75;

/// Measured Material 3 `Switch` RenderBox sizes on Flutter 3.47.7: a bare
/// `Switch` (padded tap target) is 60x48, while the shrink-wrapped switch
/// inside `SwitchListTile` is 60x40. The wrappers below keep these layout
/// sizes times [kDesktopSwitchScale] so rows neither grow nor leave a gap.
const Size kBareSwitchSize = Size(60, 48);
const Size kTileSwitchSize = Size(60, 40);

/// A [Switch] that draws at [kDesktopSwitchScale] on the desktop shell.
///
/// Phone/compact layouts get the plain `Switch` unchanged. On desktop the
/// switch is painted scaled inside a matching scaled box, so the row keeps
/// no leftover height or right-hand gap. Colours, states and callbacks are
/// untouched; hit testing still flows through the scaled switch.
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.trackColor,
    this.trackOutlineColor,
    this.thumbIcon,
    this.materialTapTargetSize,
    this.dragStartBehavior = DragStartBehavior.start,
    this.mouseCursor,
    this.focusColor,
    this.hoverColor,
    this.overlayColor,
    this.splashRadius,
    this.focusNode,
    this.onFocusChange,
    this.autofocus = false,
    this.padding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeThumbColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final WidgetStateProperty<Color?>? thumbColor;
  final WidgetStateProperty<Color?>? trackColor;
  final WidgetStateProperty<Color?>? trackOutlineColor;
  final WidgetStateProperty<Icon?>? thumbIcon;
  final MaterialTapTargetSize? materialTapTargetSize;
  final DragStartBehavior dragStartBehavior;
  final MouseCursor? mouseCursor;
  final Color? focusColor;
  final Color? hoverColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final double? splashRadius;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final control = Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeThumbColor,
      activeTrackColor: activeTrackColor,
      inactiveThumbColor: inactiveThumbColor,
      inactiveTrackColor: inactiveTrackColor,
      thumbColor: thumbColor,
      trackColor: trackColor,
      trackOutlineColor: trackOutlineColor,
      thumbIcon: thumbIcon,
      materialTapTargetSize: materialTapTargetSize,
      dragStartBehavior: dragStartBehavior,
      mouseCursor: mouseCursor,
      focusColor: focusColor,
      hoverColor: hoverColor,
      overlayColor: overlayColor,
      splashRadius: splashRadius,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      autofocus: autofocus,
      padding: padding,
    );
    if (!context.usesDesktopShell) return control;
    return _ScaledSwitchBox(baseSize: kBareSwitchSize, child: control);
  }
}

/// A [SwitchListTile] that draws its switch at [kDesktopSwitchScale] on the
/// desktop shell.
///
/// Phone/compact layouts get the plain `SwitchListTile` unchanged. On desktop
/// the row is a [ListTile] with the same title, subtitle, padding and tap
/// behaviour as `SwitchListTile`, plus the scaled switch where the tile puts
/// it (leading stays leading, everything else goes trailing, matching
/// `SwitchListTile`'s own placement).
class CompactSwitchListTile extends StatelessWidget {
  const CompactSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.secondary,
    this.dense,
    this.controlAffinity,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? secondary;
  final bool? dense;
  final ListTileControlAffinity? controlAffinity;

  @override
  Widget build(BuildContext context) {
    if (!context.usesDesktopShell) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
        secondary: secondary,
        dense: dense,
        controlAffinity: controlAffinity,
      );
    }
    final control = _ScaledSwitchBox(
      baseSize: kTileSwitchSize,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    final Widget? leading;
    final Widget? trailing;
    if (controlAffinity == ListTileControlAffinity.leading) {
      leading = control;
      trailing = secondary;
    } else {
      leading = secondary;
      trailing = control;
    }
    return MergeSemantics(
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        dense: dense,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        onTap: onChanged != null ? () => onChanged!(!value) : null,
      ),
    );
  }
}

/// Paints [child] (a full-size switch) at [kDesktopSwitchScale] inside a box
/// of the correspondingly scaled size, so surrounding rows keep no leftover
/// height or gap. [FittedBox] lays the switch out at its natural size and
/// then scales paint and hit testing uniformly; a [Transform.scale] under
/// the tight box would squeeze the switch before scaling it.
class _ScaledSwitchBox extends StatelessWidget {
  const _ScaledSwitchBox({required this.baseSize, required this.child});

  final Size baseSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: Size(
        baseSize.width * kDesktopSwitchScale,
        baseSize.height * kDesktopSwitchScale,
      ),
      child: FittedBox(child: child),
    );
  }
}
