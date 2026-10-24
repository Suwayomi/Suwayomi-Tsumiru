import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

const double kDesktopSwitchScale = 0.75;

/// Flutter 3.47.7 switch sizes: 60×48 bare, 60×40 inside SwitchListTile.
const Size kBareSwitchSize = Size(60, 48);
const Size kTileSwitchSize = Size(60, 40);

/// Scale desktop paint and layout together; compact layouts use the plain Switch.
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

/// Scale the desktop switch while retaining SwitchListTile placement; compact layouts use it unchanged.
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

/// FittedBox scales natural switch layout and hit testing; Transform.scale would squeeze it first.
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
