import 'package:flutter/material.dart';

class SettingsPaneScope extends InheritedWidget {
  const SettingsPaneScope({
    super.key,
    required this.nested,
    required this.onClose,
    required this.onBack,
    this.tabs,
    this.width = 720,
    required super.child,
  });

  final double width;
  final Widget? tabs;
  final bool nested;
  final VoidCallback onClose;
  final VoidCallback onBack;

  static SettingsPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) =>
      width != oldWidget.width ||
      tabs != oldWidget.tabs ||
      nested != oldWidget.nested ||
      onClose != oldWidget.onClose ||
      onBack != oldWidget.onBack;
}
