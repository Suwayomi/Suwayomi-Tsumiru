import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;

final textureLimitProvider = FutureProvider<int?>((ref) => deviceTextureLimit);

final Future<int?> deviceTextureLimit = _probeTextureLimit();

Future<int?> _probeTextureLimit() async {
  final override = int.tryParse(
    const String.fromEnvironment('TSUMIRU_TEXTURE_LIMIT'),
  );
  if (override != null && override > 0) return override;
  final bytes = img.encodePng(img.Image(width: 1, height: 32768));
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final height = frame.image.height;
    frame.image.dispose();
    return height < 32768 ? height : null;
  } finally {
    codec.dispose();
  }
}

ui.TargetImageSize? textureLimitedSize(int width, int height, int? limit) {
  if (limit == null || math.max(width, height) <= limit) return null;
  final scale = limit / math.max(width, height);
  return ui.TargetImageSize(
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

Future<ui.Codec> decodeWithinTextureLimit(
  ui.ImmutableBuffer buffer,
  ImageDecoderCallback decode, {
  ui.TargetImageSizeCallback? getTargetSize,
}) async {
  final limit = await deviceTextureLimit;
  if (limit == null) return decode(buffer, getTargetSize: getTargetSize);
  return decode(
    buffer,
    getTargetSize: (width, height) {
      final capped = textureLimitedSize(width, height, limit);
      final requested = getTargetSize?.call(width, height);
      if (capped == null) return requested ?? ui.TargetImageSize();
      final scale = math.min(
        limit / math.max(width, height),
        math.min(
          (requested?.width ?? width) / width,
          (requested?.height ?? height) / height,
        ),
      );
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    },
  );
}

class TextureLimitedImageProvider extends ImageProvider<Object> {
  const TextureLimitedImageProvider(this.imageProvider);

  final ImageProvider imageProvider;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      imageProvider.obtainKey(configuration);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      imageProvider.loadImage(
        key,
        (buffer, {getTargetSize}) => decodeWithinTextureLimit(
          buffer,
          decode,
          getTargetSize: getTargetSize,
        ),
      );
}

class TextureLimitedNetworkImageProvider extends CachedNetworkImageProvider {
  const TextureLimitedNetworkImageProvider(
    super.url, {
    super.cacheKey,
    super.cacheManager,
    super.headers,
    super.imageRenderMethodForWeb,
  });

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) => super.loadImage(
    key,
    (buffer, {getTargetSize}) => decodeWithinTextureLimit(
      buffer,
      decode,
      getTargetSize: getTargetSize,
    ),
  );
}
