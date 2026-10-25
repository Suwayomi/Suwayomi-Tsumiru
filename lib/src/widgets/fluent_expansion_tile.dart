import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../utils/motion/reduce_motion.dart';

class FluentExpansionTile extends StatefulWidget {
  const FluentExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.dense,
    this.expandedCrossAxisAlignment,
    this.tilePadding,
    this.shape,
    this.collapsedShape,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool? dense;
  final CrossAxisAlignment? expandedCrossAxisAlignment;
  final EdgeInsetsGeometry? tilePadding;
  final ShapeBorder? shape;
  final ShapeBorder? collapsedShape;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<FluentExpansionTile> createState() => _FluentExpansionTileState();
}

class _FluentExpansionTileState extends State<FluentExpansionTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: widget.title,
      subtitle: widget.subtitle,
      dense: widget.dense,
      expandedCrossAxisAlignment: widget.expandedCrossAxisAlignment,
      tilePadding: widget.tilePadding,
      shape: widget.shape,
      collapsedShape: widget.collapsedShape,
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onExpansionChanged?.call(expanded);
      },
      trailing: AnimatedRotation(
        turns: _expanded ? 0.5 : 0,
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        child: const Icon(FluentIcons.chevron_down_24_regular),
      ),
      children: widget.children,
    );
  }
}
