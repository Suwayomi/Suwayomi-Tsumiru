// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../../constants/enum.dart';
import '../../../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../../../widgets/server_image.dart';
import 'paged_spread_mapping.dart';
import 'rotate_wide_page.dart';

/// Logical-pixel dead space between paired pages or around a wide page.
const double kCenterMargin = 16.0;

class DoublePageView extends StatelessWidget {
  const DoublePageView({
    super.key,
    required this.entry,
    required this.pages,
    required this.pageFit,
    required this.pageSize,
    required this.centerMargin,
    required this.rotateWide,
    required this.rotateWideInvert,
    required this.reversePair,
    required this.onPageWide,
    required this.onNaturalSize,
    this.naturalSize = false,
    this.cropBorders = false,
  });

  final SpreadEntry entry;

  final List<String> pages;

  /// Fit and decode caps match full-page rendering in the single-page viewer.
  final BoxFit? pageFit;
  final Size? pageSize;

  final CenterMarginType centerMargin;
  final bool rotateWide;
  final bool rotateWideInvert;

  /// Swap slot order within a pair (invertDoublePages XOR RTL).
  final bool reversePair;

  /// Reports a page's wide/portrait aspect once its image resolves, so the
  /// mapping can isolate/split it. Fires only for full-page slots.
  final void Function(int raw, bool isWide) onPageWide;

  /// Reports a page's decoded pixel size, which the viewport needs to place a
  /// page at its own size (Original size) and to bound panning.
  final void Function(int raw, Size natural) onNaturalSize;

  /// Render at decoded size for 1:1; magnifying a fitted image would blur it.
  final bool naturalSize;

  final bool cropBorders;

  bool get _marginOnDouble =>
      centerMargin == CenterMarginType.doublePage ||
      centerMargin == CenterMarginType.doubleAndWide;
  bool get _marginOnWide =>
      centerMargin == CenterMarginType.widePage ||
      centerMargin == CenterMarginType.doubleAndWide;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Center(child: CenterSorayomiShimmerIndicator());
    }

    if (entry.first.half != PageHalf.full) {
      return _slot(entry.first);
    }

    if (!entry.isPair) {
      final wide = _slot(entry.first);
      if (_marginOnWide) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kCenterMargin),
          child: wide,
        );
      }
      return wide;
    }

    final ordered = reversePair
        ? [entry.second!, entry.first]
        : [entry.first, entry.second!];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _slot(ordered[0], alignment: Alignment.centerRight),
        ),
        if (_marginOnDouble) const SizedBox(width: kCenterMargin),
        Expanded(
          child: _slot(ordered[1], alignment: Alignment.centerLeft),
        ),
      ],
    );
  }

  Widget _slot(PageUnit unit, {Alignment alignment = Alignment.center}) {
    if (unit.raw >= pages.length) {
      return const Center(child: CenterSorayomiShimmerIndicator());
    }
    return ServerImage(
      showReloadButton: true,
      fit: pageFit,
      size: pageSize,
      appendApiToUrl: false,
      cropBorders: cropBorders,
      imageUrl: pages[unit.raw],
      imageBuilder: (context, imageProvider) => _SpreadImage(
        imageProvider: imageProvider,
        raw: unit.raw,
        half: unit.half,
        rotateWide: rotateWide,
        rotateWideInvert: rotateWideInvert,
        fit: pageFit ?? BoxFit.contain,
        alignment: alignment,
        onPageWide: onPageWide,
        onNaturalSize: onNaturalSize,
        naturalSize: naturalSize,
      ),
      progressIndicatorBuilder: (context, url, downloadProgress) =>
          CenterSorayomiShimmerIndicator(value: downloadProgress.progress),
    );
  }
}

class _SpreadImage extends StatefulWidget {
  const _SpreadImage({
    required this.imageProvider,
    required this.raw,
    required this.half,
    required this.rotateWide,
    required this.rotateWideInvert,
    required this.fit,
    required this.alignment,
    required this.onPageWide,
    required this.onNaturalSize,
    required this.naturalSize,
  });

  final ImageProvider imageProvider;
  final int raw;
  final PageHalf half;
  final bool rotateWide;
  final bool rotateWideInvert;
  final BoxFit fit;
  final Alignment alignment;
  final void Function(int raw, bool isWide) onPageWide;
  final void Function(int raw, Size natural) onNaturalSize;
  final bool naturalSize;

  @override
  State<_SpreadImage> createState() => _SpreadImageState();
}

class _SpreadImageState extends State<_SpreadImage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage);
  bool _isWide = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_SpreadImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _resolve();
  }

  // The provider is already decoded by imageBuilder, so resolving it here is a cache hit.
  void _resolve() {
    final stream =
        widget.imageProvider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final wide = info.image.width > info.image.height;
    final w = info.image.width.toDouble();
    final h = info.image.height.toDouble();
    // Rotating a wide page swaps its axes, so report the size as drawn.
    final natural =
        widget.rotateWide && wide ? Size(h, w) : Size(w, h);
    info.dispose();
    // Only full-page slots drive wide-detection; a half is already known wide.
    if (widget.half == PageHalf.full) {
      widget.onPageWide(widget.raw, wide);
      widget.onNaturalSize(widget.raw, natural);
    }
    if (wide == _isWide) return;
    if (synchronousCall) {
      _isWide = wide;
    } else if (mounted) {
      setState(() => _isWide = wide);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.half != PageHalf.full) {
      final alignment = widget.half == PageHalf.left
          ? Alignment.centerLeft
          : Alignment.centerRight;
      return FittedBox(
        fit: BoxFit.contain,
        child: ClipRect(
          child: Align(
            alignment: alignment,
            widthFactor: 0.5,
            child: Image(image: widget.imageProvider),
          ),
        ),
      );
    }

    // Original size overflows the slot on purpose; the viewport clips per-page
    // and its zoom pans the overflow.
    final Widget image = widget.naturalSize
        ? OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: widget.alignment,
            child: Image(image: widget.imageProvider),
          )
        : Image(
            image: widget.imageProvider,
            fit: widget.fit,
            alignment: widget.alignment,
          );
    if (widget.rotateWide && _isWide) {
      return RotatedBox(
        quarterTurns: widget.rotateWideInvert ? -1 : 1,
        child: image,
      );
    }
    return image;
  }
}
