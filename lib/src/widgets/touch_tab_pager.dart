import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TouchTabPager extends StatelessWidget {
  const TouchTabPager({
    super.key,
    required this.children,
    this.controller,
    this.physics,
  });

  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: behavior.dragDevices.difference({PointerDeviceKind.mouse}),
      ),
      child: TabBarView(
        controller: controller,
        physics: physics,
        children: [
          for (final child in children)
            ScrollConfiguration(behavior: behavior, child: child),
        ],
      ),
    );
  }
}
