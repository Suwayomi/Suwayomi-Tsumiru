// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../constants/app_sizes.dart';
import '../../utils/extensions/custom_extensions.dart';

enum DesktopPageLayout {
  standard(
    EdgeInsetsDirectional.only(
      start: kDesktopPageInset,
      top: kDesktopPageInset,
    ),
  ),

  header(EdgeInsetsDirectional.only(start: kDesktopPageInset)),
  fullBleed(EdgeInsetsDirectional.zero);

  const DesktopPageLayout(this.insets);

  final EdgeInsetsDirectional insets;
}

const kDesktopListMaxWidth = 1040.0;

const kDesktopSettingsMaxWidth = 720.0;

/// Insets the desktop page area by the visible page's [DesktopPageLayout].
class DesktopPageFrame extends StatelessWidget {
  const DesktopPageFrame({
    super.key,
    this.wrapsNavigator = false,
    required this.child,
  });

  /// True when [child] is a navigator whose pages are the framed pages.
  final bool wrapsNavigator;
  final Widget child;

  @override
  Widget build(BuildContext context) => _DesktopPageFrameScope(
    routeSettings: wrapsNavigator ? ModalRoute.settingsOf(context) : null,
    child: _DesktopPageFrameBox(child: child),
  );
}

class _DesktopPageFrameScope extends InheritedWidget {
  const _DesktopPageFrameScope({
    required this.routeSettings,
    required super.child,
  });

  final RouteSettings? routeSettings;

  @override
  bool updateShouldNotify(_DesktopPageFrameScope oldWidget) => false;
}

/// False in overlays, dialogs, sheets and menus opened over a page.
bool isOnDesktopPage(BuildContext context) {
  if (!context.usesDesktopShell) return false;
  final frame = context.getInheritedWidgetOfExactType<_DesktopPageFrameScope>();
  if (frame == null || ModalRoute.opaqueOf(context) == false) return false;
  final settings = frame.routeSettings;
  return settings == null ||
      !identical(ModalRoute.settingsOf(context), settings);
}

bool desktopScrollReservesGutter(BuildContext context) {
  if (!isOnDesktopPage(context) ||
      context.getInheritedWidgetOfExactType<DesktopFullBleedScroll>() != null) {
    return false;
  }
  var reservesGutter = true;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is _DesktopPageFrameScope) return false;
    if (widget is Drawer ||
        widget is Card ||
        widget is EditableText ||
        (widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical)) {
      reservesGutter = false;
      return false;
    }
    return true;
  });
  return reservesGutter;
}

/// Scroll views below paint edge to edge; page-line content keeps clear of the thumb.
class DesktopFullBleedScroll extends InheritedWidget {
  const DesktopFullBleedScroll({super.key, required super.child});

  @override
  bool updateShouldNotify(DesktopFullBleedScroll oldWidget) => false;
}

class _DesktopPageFrameBox extends SingleChildRenderObjectWidget {
  const _DesktopPageFrameBox({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDesktopPageFrame(
        desktop: context.usesDesktopShell,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDesktopPageFrame)
      ..desktop = context.usesDesktopShell
      ..textDirection = Directionality.of(context);
  }
}

/// Declares the layout of the page it wraps while that page is visible.
class DesktopPageLayoutScope extends StatefulWidget {
  const DesktopPageLayoutScope({
    super.key,
    required this.layout,
    required this.child,
  });

  final DesktopPageLayout layout;
  final Widget child;

  @override
  State<DesktopPageLayoutScope> createState() => _DesktopPageLayoutScopeState();
}

class _DesktopPageLayoutScopeState extends State<DesktopPageLayoutScope> {
  _RenderDesktopPageFrame? _frame;

  void _declare() {
    // Covered pages go offstage and lose ticker mode; popups above keep it.
    final visible = TickerMode.valuesOf(context).enabled;
    final frame = context
        .findAncestorRenderObjectOfType<_RenderDesktopPageFrame>();
    if (frame != _frame) _frame?.declare(this, null);
    _frame = frame;
    frame?.declare(this, visible ? widget.layout : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _declare();
  }

  @override
  void didUpdateWidget(DesktopPageLayoutScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) _declare();
  }

  @override
  void activate() {
    super.activate();
    _declare();
  }

  @override
  void deactivate() {
    _frame?.declare(this, null);
    _frame = null;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) =>
      _DesktopPageLayoutMarker(layout: widget.layout, child: widget.child);
}

class _DesktopPageLayoutMarker extends InheritedWidget {
  const _DesktopPageLayoutMarker({required this.layout, required super.child});

  final DesktopPageLayout layout;

  @override
  bool updateShouldNotify(_DesktopPageLayoutMarker oldWidget) =>
      layout != oldWidget.layout;
}

DesktopPageLayout? _pageLayout(BuildContext context) =>
    context.getInheritedWidgetOfExactType<_DesktopPageLayoutMarker>()?.layout;

/// The frame supplies the page line except on full-bleed pages.
double _pageLine(BuildContext context) =>
    _pageLayout(context) == DesktopPageLayout.fullBleed ? kDesktopPageInset : 0;

/// Content of a full-bleed scroll view stays clear of the scrollbar itself.
double _endClearance(BuildContext context, double end) =>
    context.getInheritedWidgetOfExactType<DesktopFullBleedScroll>() == null
    ? end
    : math.max(end, kDesktopScrollbarGutter);

double desktopPageLineStart(BuildContext context, double inset) =>
    isOnDesktopPage(context) ? _pageLine(context) : inset;

extension DesktopPageLine on EdgeInsets {
  /// On desktop pages, puts a block's start (and with [top], its top) on the page line.
  EdgeInsets onDesktopPageLine(BuildContext context, {bool top = false}) {
    if (!isOnDesktopPage(context)) return this;
    final line = _pageLine(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return EdgeInsets.fromLTRB(
      ltr ? line : _endClearance(context, left),
      top ? line : this.top,
      ltr ? _endClearance(context, right) : line,
      bottom,
    );
  }
}

extension DesktopPageLineDirectional on EdgeInsetsDirectional {
  EdgeInsetsDirectional onDesktopPageLine(
    BuildContext context, {
    bool top = false,
  }) {
    if (!isOnDesktopPage(context)) return this;
    final line = _pageLine(context);
    return EdgeInsetsDirectional.fromSTEB(
      line,
      top ? line : this.top,
      _endClearance(context, end),
      bottom,
    );
  }
}

class DesktopSliverGutterClearance extends StatelessWidget {
  const DesktopSliverGutterClearance({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) => isOnDesktopPage(context)
      ? SliverPadding(
          padding: EdgeInsetsDirectional.only(end: _endClearance(context, 0)),
          sliver: sliver,
        )
      : sliver;
}

/// Leading spacer that the frame's top inset replaces on desktop pages.
class DesktopPageLeadingGap extends StatelessWidget {
  const DesktopPageLeadingGap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: isOnDesktopPage(context) ? _pageLine(context) : height);
}

class DesktopCentredColumn extends StatelessWidget {
  const DesktopCentredColumn({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kDesktopListMaxWidth),
      child: child,
    ),
  );
}

class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({super.key, required this.child});

  static const double gap = kDesktopPageInset;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: gap),
    child: child,
  );
}

abstract class _DesktopBleed extends SingleChildRenderObjectWidget {
  const _DesktopBleed({
    super.key,
    required this.start,
    required this.top,
    required super.child,
  }) : end = 0;

  const _DesktopBleed.coverGrid({super.key, required super.child})
    : start = kMangaCoverCardInset / 2,
      top = kMangaCoverCardInset / 2,
      end = kMangaCoverCardInset / 2;

  final double start;
  final double top;
  final double end;
}

EdgeInsets _resolveDesktopBleed(BuildContext context, _DesktopBleed bleed) =>
    isOnDesktopPage(context)
    ? EdgeInsetsDirectional.fromSTEB(
        bleed.start,
        bleed.top,
        bleed.end,
        0,
      ).resolve(Directionality.of(context))
    : EdgeInsets.zero;

/// Lets a sliver's transparent outer inset sit outside the page line on desktop.
class DesktopSliverBleed extends _DesktopBleed {
  const DesktopSliverBleed({
    super.key,
    required super.start,
    required Widget sliver,
  }) : super(top: start, child: sliver);

  /// Card margins are transparent on every edge of a cover grid.
  const DesktopSliverBleed.coverGrid({super.key, required Widget sliver})
    : super.coverGrid(child: sliver);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDesktopSliverBleed(_resolveDesktopBleed(context, this));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDesktopSliverBleed).bleed =
        _resolveDesktopBleed(context, this);
  }
}

/// Box form of [DesktopSliverBleed], clipped like a viewport.
class DesktopBoxBleed extends _DesktopBleed {
  const DesktopBoxBleed({
    super.key,
    required super.start,
    super.top = 0,
    required super.child,
  });

  const DesktopBoxBleed.coverGrid({super.key, required super.child})
    : super.coverGrid();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDesktopBoxBleed(_resolveDesktopBleed(context, this));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDesktopBoxBleed).bleed =
        _resolveDesktopBleed(context, this);
  }
}

class _RenderDesktopBoxBleed extends RenderShiftedBox {
  _RenderDesktopBoxBleed(this._bleed) : super(null);

  EdgeInsets _bleed;
  set bleed(EdgeInsets value) {
    if (value == _bleed) return;
    _bleed = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final extra = _bleed.horizontal;
    return constraints.copyWith(
      minWidth: constraints.minWidth + extra,
      maxWidth: constraints.maxWidth + extra,
      minHeight: constraints.minHeight + _bleed.top,
      maxHeight: constraints.maxHeight + _bleed.top,
    );
  }

  Size _size(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        Size(
          childSize.width - _bleed.horizontal,
          childSize.height - _bleed.top,
        ),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _size(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(
      -_bleed.left,
      -_bleed.top,
    );
    size = _size(constraints, child.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_bleed == EdgeInsets.zero) return super.paint(context, offset);
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

class _RenderDesktopSliverBleed extends RenderSliver
    with RenderObjectWithChildMixin<RenderSliver> {
  _RenderDesktopSliverBleed(this._bleed);

  EdgeInsets _bleed;
  set bleed(EdgeInsets value) {
    if (value == _bleed) return;
    _bleed = value;
    markNeedsLayout();
  }

  EdgeInsets get _active =>
      constraints.axisDirection == AxisDirection.down &&
          constraints.growthDirection == GrowthDirection.forward
      ? _bleed
      : EdgeInsets.zero;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalParentData) {
      child.parentData = SliverPhysicalParentData();
    }
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    final bleed = _active;
    child.layout(
      constraints.copyWith(
        scrollOffset: constraints.scrollOffset + bleed.top,
        precedingScrollExtent: math.max(
          0,
          constraints.precedingScrollExtent - bleed.top,
        ),
        crossAxisExtent: constraints.crossAxisExtent + bleed.horizontal,
      ),
      parentUsesSize: true,
    );
    final childGeometry = child.geometry!;
    if (childGeometry.scrollOffsetCorrection != null) {
      geometry = SliverGeometry(
        scrollOffsetCorrection: childGeometry.scrollOffsetCorrection,
      );
      return;
    }
    geometry = SliverGeometry(
      scrollExtent: math.max(0, childGeometry.scrollExtent - bleed.top),
      paintExtent: childGeometry.paintExtent,
      paintOrigin: childGeometry.paintOrigin,
      layoutExtent: childGeometry.layoutExtent,
      maxPaintExtent: math.max(0, childGeometry.maxPaintExtent - bleed.top),
      maxScrollObstructionExtent: childGeometry.maxScrollObstructionExtent,
      hitTestExtent: childGeometry.hitTestExtent,
      visible: childGeometry.visible,
      hasVisualOverflow:
          childGeometry.hasVisualOverflow || bleed != EdgeInsets.zero,
      cacheExtent: childGeometry.cacheExtent,
    );
    (child.parentData! as SliverPhysicalParentData).paintOffset = Offset(
      -bleed.left,
      0,
    );
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final child = this.child;
    if (child == null || child.geometry!.hitTestExtent <= 0) return false;
    return result.addWithAxisOffset(
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
      mainAxisOffset: 0,
      crossAxisOffset: childCrossAxisPosition(child),
      paintOffset: (child.parentData! as SliverPhysicalParentData).paintOffset,
      hitTest: child.hitTest,
    );
  }

  @override
  double childMainAxisPosition(RenderSliver child) => 0;

  @override
  double childCrossAxisPosition(RenderSliver child) => -_active.left;

  @override
  double? childScrollOffset(RenderObject child) => -_active.top;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    (child.parentData! as SliverPhysicalParentData).applyPaintTransform(
      transform,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !child.geometry!.visible) return;
    context.paintChild(
      child,
      offset + (child.parentData! as SliverPhysicalParentData).paintOffset,
    );
  }
}

class _RenderDesktopPageFrame extends RenderShiftedBox {
  _RenderDesktopPageFrame({
    required bool desktop,
    required TextDirection textDirection,
  }) : _desktop = desktop,
       _textDirection = textDirection,
       super(null);

  bool _desktop;
  set desktop(bool value) {
    if (value == _desktop) return;
    _desktop = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  final Map<Object, DesktopPageLayout> _declared = {};

  /// The most recently mounted visible page wins, so a pushed page beats the one beneath it.
  void declare(Object owner, DesktopPageLayout? layout) {
    final before = _layout;
    if (layout == null) {
      _declared.remove(owner);
    } else {
      _declared[owner] = layout;
    }
    if (_layout != before && attached) markNeedsLayout();
  }

  DesktopPageLayout get _layout =>
      _declared.isEmpty ? DesktopPageLayout.standard : _declared.values.last;

  EdgeInsets get _insets =>
      _desktop ? _layout.insets.resolve(_textDirection) : EdgeInsets.zero;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final insets = _insets;
    final childSize =
        child?.getDryLayout(constraints.deflate(insets)) ?? Size.zero;
    return constraints.constrain(
      Size(
        childSize.width + insets.horizontal,
        childSize.height + insets.vertical,
      ),
    );
  }

  @override
  void performLayout() {
    final insets = _insets;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(insets.horizontal, insets.vertical));
      return;
    }
    child.layout(constraints.deflate(insets), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(
      insets.left,
      insets.top,
    );
    size = constraints.constrain(
      Size(
        child.size.width + insets.horizontal,
        child.size.height + insets.vertical,
      ),
    );
  }
}
