// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'avif_codec.dart';
import 'avif_file_io.dart';

@immutable
class AvifAwareFileImage extends ImageProvider<AvifAwareFileImage> {
  const AvifAwareFileImage(this.file, {this.scale = 1.0});

  final File file;
  final double scale;

  @override
  Future<AvifAwareFileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AvifAwareFileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: key._loadCodec(decode),
    scale: key.scale,
    debugLabel: key.file.path,
    informationCollector: () => <DiagnosticsNode>[
      ErrorDescription('Path: ${key.file.path}'),
    ],
  );

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final length = await file.length();
    if (length == 0) {
      PaintingBinding.instance.imageCache.evict(this);
      throw StateError('$file is empty and cannot be loaded as an image.');
    }
    return decode(await _buffer());
  }

  Future<ui.ImmutableBuffer> _buffer() async {
    if (avifNormalizationSupported && await isAvifFile(file)) {
      final bytes = await normalizeAvifBytes(await file.readAsBytes());
      return ui.ImmutableBuffer.fromUint8List(bytes);
    }
    return ui.ImmutableBuffer.fromFilePath(file.path);
  }

  @override
  bool operator ==(Object other) =>
      other is AvifAwareFileImage &&
      other.file.path == file.path &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, scale);

  @override
  String toString() => 'AvifAwareFileImage("${file.path}", scale: $scale)';
}
