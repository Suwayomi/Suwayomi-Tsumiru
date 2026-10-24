// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Rotates wide pages ±90°; aspect lookup reuses the decoded image without fetching again.
class RotateWidePage extends StatefulWidget {
  const RotateWidePage({
    super.key,
    required this.imageProvider,
    required this.invert,
    this.fit = BoxFit.contain,
  });

  final ImageProvider imageProvider;
  final bool invert;
  final BoxFit fit;

  @override
  State<RotateWidePage> createState() => _RotateWidePageState();
}

class _RotateWidePageState extends State<RotateWidePage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage);
  bool _isWide = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(RotateWidePage oldWidget) {
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
    final image = Image(image: widget.imageProvider, fit: widget.fit);
    if (!_isWide) return image;
    return RotatedBox(quarterTurns: widget.invert ? -1 : 1, child: image);
  }
}
