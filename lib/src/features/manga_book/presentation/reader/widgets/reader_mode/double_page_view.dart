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

/// Gap (logical px) inserted by CenterMarginType — a foldable-style dead space
/// between paired pages / around a wide page.
const double kCenterMargin = 16.0;

/// Renders one [SpreadEntry] for the horizontal paged viewer: a single page, a
/// side-by-side pair (double), or a clipped half of a wide page (split). Each
/// page reuses [ServerImage] for loading/reload/progress, so per-page settings
/// (image scale, rotate-wide) behave exactly as the single-page path.
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
  });

  final SpreadEntry entry;

  /// Raw page URLs (`chapterPages.pages`).
  final List<String> pages;

  /// Per-page image fit + decode-size (from ImageScaleType.pagedFit) — matches
  /// the single-page render for a full page.
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

    // Split half — one half of a wide page fills the item.
    if (entry.first.half != PageHalf.full) {
      return _slot(entry.first);
    }

    // Single full page (single mode, or a solo/wide page in double mode).
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

    // Pair — two pages side by side, each taking half the width.
    final left = _slot(entry.first);
    final right = _slot(entry.second!);
    final ordered = reversePair ? [right, left] : [left, right];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: ordered[0]),
        if (_marginOnDouble) const SizedBox(width: kCenterMargin),
        Expanded(child: ordered[1]),
      ],
    );
  }

  Widget _slot(PageUnit unit) {
    if (unit.raw >= pages.length) {
      return const Center(child: CenterSorayomiShimmerIndicator());
    }
    return ServerImage(
      showReloadButton: true,
      fit: pageFit,
      size: pageSize,
      appendApiToUrl: false,
      imageUrl: pages[unit.raw],
      imageBuilder: (context, imageProvider) => _SpreadImage(
        imageProvider: imageProvider,
        raw: unit.raw,
        half: unit.half,
        rotateWide: rotateWide,
        rotateWideInvert: rotateWideInvert,
        fit: pageFit ?? BoxFit.contain,
        onPageWide: onPageWide,
      ),
      progressIndicatorBuilder: (context, url, downloadProgress) =>
          CenterSorayomiShimmerIndicator(value: downloadProgress.progress),
    );
  }
}

/// Renders a decoded page fragment: measures aspect (reports wide), then draws
/// the full page (optionally rotated) or a clipped left/right half. Aspect is
/// resolved from the already-decoded provider (imageBuilder only fires after
/// load, so this is a cache hit — never a new fetch), the same technique as
/// [RotateWidePage].
class _SpreadImage extends StatefulWidget {
  const _SpreadImage({
    required this.imageProvider,
    required this.raw,
    required this.half,
    required this.rotateWide,
    required this.rotateWideInvert,
    required this.fit,
    required this.onPageWide,
  });

  final ImageProvider imageProvider;
  final int raw;
  final PageHalf half;
  final bool rotateWide;
  final bool rotateWideInvert;
  final BoxFit fit;
  final void Function(int raw, bool isWide) onPageWide;

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

  void _resolve() {
    final stream =
        widget.imageProvider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final wide = info.image.width > info.image.height;
    info.dispose();
    // Only full-page slots drive wide-detection; a half is already known wide.
    if (widget.half == PageHalf.full) {
      widget.onPageWide(widget.raw, wide);
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
    // Split half: clip to half the natural width, then scale to fit the slot.
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

    final image = Image(image: widget.imageProvider, fit: widget.fit);
    if (widget.rotateWide && _isWide) {
      return RotatedBox(
        quarterTurns: widget.rotateWideInvert ? -1 : 1,
        child: image,
      );
    }
    return image;
  }
}
