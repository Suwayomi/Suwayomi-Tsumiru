import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SeriesInfoExpansion extends ChangeNotifier {
  final fullContentKey = GlobalKey();
  final visibleContentKey = GlobalKey();
  bool isExpanded = false;
  bool isAutomatic = false;
  bool _manuallyCollapsed = false;

  void toggle() {
    _manuallyCollapsed = isExpanded;
    isExpanded = !isExpanded;
    isAutomatic = false;
    notifyListeners();
  }

  void updateFit(double columnHeight, double viewportHeight) {
    if (_manuallyCollapsed) return;
    final full = fullContentKey.currentContext?.size;
    final visible = visibleContentKey.currentContext?.size;
    if (full == null || visible == null) return;
    final fullHeight = columnHeight - visible.height + full.height;
    final fits = fullHeight <= viewportHeight - (isAutomatic ? 0 : 24);
    if (fits == isAutomatic) return;
    isAutomatic = fits;
    isExpanded = fits;
    notifyListeners();
  }
}

class SeriesInfoColumn extends StatefulWidget {
  const SeriesInfoColumn({
    super.key,
    required this.expansion,
    required this.builder,
  });

  final SeriesInfoExpansion expansion;

  final Widget Function(SeriesInfoExpansion expansion) builder;

  @override
  State<SeriesInfoColumn> createState() => _SeriesInfoColumnState();
}

class _SeriesInfoColumnState extends State<SeriesInfoColumn> {
  SeriesInfoExpansion get expansion => widget.expansion;
  final columnKey = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: _ObserveInfoLayout(
        onLayout: () {
          if (!mounted) return;
          final size = columnKey.currentContext?.size;
          if (size != null) {
            expansion.updateFit(size.height, constraints.maxHeight);
          }
        },
        child: SizedBox(key: columnKey, child: widget.builder(expansion)),
      ),
    ),
  );
}

class _ObserveInfoLayout extends SingleChildRenderObjectWidget {
  const _ObserveInfoLayout({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderObserveInfoLayout(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderObserveInfoLayout renderObject,
  ) {
    renderObject.onLayout = onLayout;
    renderObject.markNeedsLayout();
  }
}

class _RenderObserveInfoLayout extends RenderProxyBox {
  _RenderObserveInfoLayout(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onLayout();
    });
  }
}
