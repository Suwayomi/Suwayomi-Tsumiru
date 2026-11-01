import 'package:flutter/widgets.dart';

class DesktopExactExtentList extends StatelessWidget {
  const DesktopExactExtentList({
    super.key,
    required this.extents,
    required this.itemBuilder,
  });

  final List<double> extents;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SliverVariedExtentList(
    itemExtentBuilder: (index, _) =>
        index < extents.length ? extents[index] : null,
    delegate: _ExactExtentDelegate(
      itemBuilder,
      childCount: extents.length,
      totalExtent: extents.fold(0, (sum, extent) => sum + extent),
    ),
  );
}

class _ExactExtentDelegate extends SliverChildBuilderDelegate {
  _ExactExtentDelegate(
    super.builder, {
    required super.childCount,
    required this.totalExtent,
  });

  final double totalExtent;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => totalExtent;
}

double desktopTextHeight(
  BuildContext context,
  String text,
  TextStyle? style, {
  double width = double.infinity,
  int maxLines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
    ellipsis: '…',
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: width.clamp(0, double.infinity));
  final height = painter.height;
  painter.dispose();
  return height;
}
