// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';
import '../utils/motion/reduce_motion.dart';

/// A titled row of covers that pages horizontally on wide layouts.
///
/// Pass [itemCount] and [itemBuilder] for a list, or [child] for a caller-owned
/// loading, error or empty body. Arrows and the edge fade only appear while the
/// list overflows. With no [title] the arrows sit above the list instead.
class CoverRowSection extends StatefulWidget {
  const CoverRowSection({
    super.key,
    this.title,
    this.subtitle,
    this.onSeeAll,
    this.padding = EdgeInsets.zero,
    this.height,
    this.itemCount,
    this.itemBuilder,
    this.separatorBuilder,
    this.child,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final EdgeInsetsGeometry padding;
  final double? height;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final Widget? child;

  @override
  State<CoverRowSection> createState() => _CoverRowSectionState();
}

class _CoverRowSectionState extends State<CoverRowSection> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSync);
  }

  @override
  void didUpdateWidget(CoverRowSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) _scheduleSync();
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleSync);
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSync() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _sync();
    });
  }

  void _sync() {
    if (!mounted) return;
    var canBack = false;
    var canForward = false;
    if (widget.itemCount != null && _controller.hasClients) {
      final position = _controller.position;
      canBack = position.pixels > position.minScrollExtent;
      canForward = position.pixels < position.maxScrollExtent;
    }
    if (canBack == _canBack && canForward == _canForward) return;
    setState(() {
      _canBack = canBack;
      _canForward = canForward;
    });
  }

  void _scrollBy(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * .8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (context.reduceMotion) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _arrow(BuildContext context, {required bool left}) {
    final enabled = left ? _canBack : _canForward;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: IconButton.outlined(
        tooltip: left ? context.l10n.back : context.l10n.next,
        onPressed: enabled ? () => _scrollBy(left ? -1 : 1) : null,
        icon: Icon(
          left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          size: 20,
        ),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(34),
          maximumSize: const Size.square(34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          foregroundColor: context.colorScheme.onSurface,
          backgroundColor: context.colorScheme.surfaceContainer,
          side: BorderSide(color: context.colorScheme.outlineVariant),
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final title = Text(widget.title!, style: context.textTheme.titleMedium);
    final subtitle = widget.subtitle;
    if (subtitle == null) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        Text(
          subtitle,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.theme.hintColor,
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final heading = _heading(context);
    final showArrows = _canBack || _canForward;
    if (context.isTablet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(
          children: [
            Expanded(child: heading),
            if (widget.onSeeAll != null)
              TextButton(
                onPressed: widget.onSeeAll,
                child: Text(context.l10n.seriesSeeAll),
              ),
            // Reserved at all times so See all lines up across sections.
            SizedBox(
              width: _arrowAreaWidth,
              child: showArrows
                  ? Row(
                      children: [
                        const SizedBox(width: 10),
                        _arrow(context, left: true),
                        const SizedBox(width: 8),
                        _arrow(context, left: false),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: widget.onSeeAll == null
          ? heading
          : Tooltip(
              message: context.l10n.seriesSeeAll,
              child: InkWell(
                onTap: widget.onSeeAll,
                child: Row(
                  children: [
                    Expanded(child: heading),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _headerlessArrows(BuildContext context) => Padding(
    padding: widget.padding,
    child: Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(context, left: true),
          const SizedBox(width: 8),
          _arrow(context, left: false),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (widget.itemCount == null) {
      return widget.child ?? const SizedBox.shrink();
    }
    _scheduleSync();
    final list = widget.separatorBuilder == null
        ? ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder!,
          )
        : ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.itemCount!,
            itemBuilder: widget.itemBuilder!,
            separatorBuilder: widget.separatorBuilder!,
          );
    final scrollable = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: list,
    );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleSync();
        return false;
      },
      child: _canForward
          ? ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  context.colorScheme.onSurface,
                  context.colorScheme.onSurface,
                  Colors.transparent,
                ],
                stops: [0, (1 - 40 / bounds.width).clamp(0, 1), 1],
              ).createShader(bounds),
              child: scrollable,
            )
          : scrollable,
    );
  }

  @override
  Widget build(BuildContext context) {
    var body = _body(context);
    // A caller-owned body (loading, error, empty) keeps its natural height.
    if (widget.height != null && widget.itemCount != null) {
      body = SizedBox(height: widget.height, child: body);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          _header(context)
        else if (context.isTablet && (_canBack || _canForward))
          _headerlessArrows(context),
        Padding(padding: widget.padding, child: body),
      ],
    );
  }
}

// 10 gap + 34 + 8 + 34: the arrows and their spacing.
const double _arrowAreaWidth = 86;
