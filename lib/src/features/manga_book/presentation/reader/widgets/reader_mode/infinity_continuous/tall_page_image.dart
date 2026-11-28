import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../../../../../../../utils/avif/avif_codec.dart';
import 'measure_size.dart';

const _stripChannel = MethodChannel('tsumiru/page_strips');
int _nextStripOwner = 0;

Future<ui.Size> tallPageIntrinsicSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await normalizeAvifBytes(await File(path).readAsBytes()),
  );
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

/// How a tall page is cut: [stripHeight] is in source pixels and each strip is
/// decoded at 1/[sampleSize] of the source resolution.
typedef TallPagePlan = ({int stripHeight, int sampleSize});

/// Upper bound on one strip, in source pixels (mirrored by the native guard).
const tallPageMaxStripHeight = 8192;
const _minStripHeight = 512;

/// Width the page is drawn at, in logical pixels.
double tallPageDisplayWidth({
  required ui.Size source,
  required double crossAxisExtent,
  required bool horizontal,
  required bool naturalSize,
}) {
  if (horizontal) {
    final height = naturalSize
        ? math.min(crossAxisExtent, source.height)
        : crossAxisExtent;
    return height * source.width / source.height;
  }
  return naturalSize
      ? math.min(crossAxisExtent, source.width)
      : crossAxisExtent;
}

/// Cut plan for a page, or null when it can be decoded whole.
///
/// A page is cut once it would be drawn taller than two viewports or taller
/// than the GPU texture limit, so no decoded strip ever covers more than two
/// screens. The page is split into the fewest strips that fit, all of the same
/// height, so the last one is never a thin leftover: when two screens set the
/// limit, every strip covers between one and two screens. Strips are
/// downsampled by a power of two while the result stays at least as wide as
/// the drawn width in device pixels.
TallPagePlan? tallPagePlan({
  required ui.Size source,
  required double displayWidth,
  required double viewportHeight,
  required double devicePixelRatio,
  required int? textureLimit,
}) {
  if (source.width <= 0 ||
      source.height <= 0 ||
      displayWidth <= 0 ||
      viewportHeight <= 0) {
    return null;
  }
  var sampleSize = 1;
  final targetWidth = displayWidth * math.max(devicePixelRatio, 1);
  while (source.width / (sampleSize * 2) >= targetWidth) {
    sampleSize *= 2;
  }
  var maxStripHeight = (2 * viewportHeight * source.width / displayWidth)
      .floor();
  if (textureLimit != null) {
    maxStripHeight = math.min(maxStripHeight, textureLimit);
  }
  maxStripHeight = maxStripHeight.clamp(
    _minStripHeight,
    tallPageMaxStripHeight,
  );
  if (source.height <= maxStripHeight) return null;
  final stripCount = (source.height / maxStripHeight).ceil();
  final stripHeight = (source.height / stripCount).ceil();
  return (stripHeight: stripHeight, sampleSize: sampleSize);
}

class _StripPixels {
  const _StripPixels(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Desktop/iOS (and Android decoder failure) path: one full decode, scaled
/// down to the strip resolution before cutting so the kept strips stay small.
List<_StripPixels> _cutStrips((String, int, int) request) {
  final (path, stripHeight, sampleSize) = request;
  final bytes = File(path).readAsBytesSync();
  var decoded = img.decodeImage(normalizeAvifBytesSync(bytes));
  if (decoded == null) throw StateError('Cannot decode page');
  final sourceHeight = decoded.height;
  if (sampleSize > 1) {
    decoded = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width / sampleSize).ceil()),
      height: math.max(1, (decoded.height / sampleSize).ceil()),
      interpolation: img.Interpolation.average,
    );
  }
  final scale = decoded.height / sourceHeight;
  final strips = <_StripPixels>[];
  for (var y = 0; y < sourceHeight; y += stripHeight) {
    final top = (y * scale).round();
    final bottom = math.min(
      ((y + stripHeight) * scale).round(),
      decoded.height,
    );
    final height = math.max(1, bottom - top);
    strips.add(
      _StripPixels(
        img
            .copyCrop(
              decoded,
              x: 0,
              y: top,
              width: decoded.width,
              height: height,
            )
            .getBytes(order: img.ChannelOrder.rgba),
        decoded.width,
        height,
      ),
    );
  }
  return strips;
}

class _TallPageSource {
  _TallPageSource(this.path, this.cacheKey, this.size, TallPagePlan plan)
    : stripHeight = plan.stripHeight,
      sampleSize = plan.sampleSize;

  final String path;
  final String cacheKey;
  final ui.Size size;
  final int stripHeight;
  final int sampleSize;
  final String owner = '${_nextStripOwner++}';
  Future<List<_StripPixels>>? _fallback;
  final _decodedStrips = <int>{};
  bool _nativeFailed = false;
  bool _disposed = false;

  int get count => (size.height / stripHeight).ceil();
  int heightAt(int index) =>
      math.min(stripHeight, size.height.toInt() - index * stripHeight);

  Future<_StripPixels> pixels(int index) async {
    if (_disposed) throw StateError('Page has been released');
    if (defaultTargetPlatform == TargetPlatform.android && !_nativeFailed) {
      try {
        final result = await _stripChannel
            .invokeMapMethod<String, dynamic>('decodeStrip', {
              'path': path,
              'owner': owner,
              'top': index * stripHeight,
              'height': heightAt(index),
              'sampleSize': sampleSize,
            });
        final pixels = _StripPixels(
          result!['rgba'] as Uint8List,
          result['width'] as int,
          result['height'] as int,
        );
        // Region decoders round sampled edges either way; allow one pixel.
        if ((pixels.width - size.width / sampleSize).abs() > 1 ||
            (pixels.height - heightAt(index) / sampleSize).abs() > 1 ||
            pixels.rgba.length != pixels.width * pixels.height * 4) {
          throw StateError('Invalid strip dimensions');
        }
        _decodedStrips.add(index);
        if (_decodedStrips.length == count) _releaseNative();
        return pixels;
      } catch (_) {
        _nativeFailed = true;
        _releaseNative();
      }
    }
    if (_disposed) throw StateError('Page has been released');
    final strips = await (_fallback ??= compute(_cutStrips, (
      path,
      stripHeight,
      sampleSize,
    )));
    return strips[index];
  }

  void _releaseNative() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(
      _stripChannel
          .invokeMethod<void>('release', {'path': path, 'owner': owner})
          .catchError((Object _) {}),
    );
  }

  void dispose() {
    _disposed = true;
    _fallback = null;
    _releaseNative();
  }
}

@immutable
class _StripImageProvider extends ImageProvider<_StripImageProvider> {
  const _StripImageProvider(this.source, this.index);

  final _TallPageSource source;
  final int index;

  @override
  Future<_StripImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _StripImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(key._load());

  Future<ImageInfo> _load() async {
    final pixels = await source.pixels(index);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.rgba,
      pixels.width,
      pixels.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return ImageInfo(image: await completer.future);
  }

  @override
  bool operator ==(Object other) =>
      other is _StripImageProvider &&
      source.cacheKey == other.source.cacheKey &&
      source.stripHeight == other.source.stripHeight &&
      source.sampleSize == other.source.sampleSize &&
      index == other.index;

  @override
  int get hashCode => Object.hash(
    source.cacheKey,
    index,
    source.stripHeight,
    source.sampleSize,
  );
}

class TallPageImage extends HookWidget {
  const TallPageImage({
    super.key,
    required this.cacheKey,
    required this.filePath,
    required this.limit,
    required this.crossAxisExtent,
    required this.horizontal,
    required this.naturalSize,
    required this.placeholder,
    required this.onSize,
    required this.fallback,
  });

  final String cacheKey;
  final Future<String> Function() filePath;

  /// GPU texture limit, or null when the device has none worth cutting for.
  final int? limit;
  final double crossAxisExtent;
  final bool horizontal;
  final bool naturalSize;
  final Widget placeholder;
  final ValueChanged<Size> onSize;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final future = useMemoized(() async {
      final path = await filePath();
      return (path: path, size: await tallPageIntrinsicSize(path));
    }, [cacheKey]);
    final snapshot = useFuture(future);
    final data = snapshot.data;
    final width = data == null
        ? 0.0
        : tallPageDisplayWidth(
            source: data.size,
            crossAxisExtent: crossAxisExtent,
            horizontal: horizontal,
            naturalSize: naturalSize,
          );
    final plan = data == null
        ? null
        : tallPagePlan(
            source: data.size,
            displayWidth: width,
            viewportHeight: MediaQuery.sizeOf(context).height,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            textureLimit: limit,
          );
    final source = useMemoized(
      () => data == null || plan == null
          ? null
          : _TallPageSource(data.path, cacheKey, data.size, plan),
      [data?.path, plan?.stripHeight, plan?.sampleSize],
    );
    useEffect(() => source?.dispose, [source]);
    final ready = useState(false);
    useEffect(() {
      ready.value = false;
      return null;
    }, [source]);
    if (snapshot.connectionState != ConnectionState.done) return placeholder;
    if (source == null) return fallback;
    final column = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < source.count; i++)
            SizedBox(
              width: width,
              height: width * source.heightAt(i) / source.size.width,
              child: _LazyStrip(
                image: _StripImageProvider(source, i),
                onFrame: () {
                  if (!ready.value && context.mounted) ready.value = true;
                },
              ),
            ),
        ],
      ),
    );
    final child = Stack(
      children: [
        Opacity(opacity: ready.value ? 1 : 0, child: column),
        if (!ready.value) Positioned.fill(child: placeholder),
      ],
    );
    return Center(
      child: ready.value ? MeasureSize(onChange: onSize, child: child) : child,
    );
  }
}

class _LazyStrip extends StatefulWidget {
  const _LazyStrip({required this.image, required this.onFrame});

  final ImageProvider image;
  final VoidCallback onFrame;

  @override
  State<_LazyStrip> createState() => _LazyStripState();
}

class _LazyStripState extends State<_LazyStrip> {
  ScrollPosition? _position;
  bool _nearViewport = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_position != position) {
      _position?.removeListener(_schedule);
      _position = position;
      position?.addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      final position = _position;
      if (box is! RenderBox ||
          !box.hasSize ||
          viewport == null ||
          position == null) {
        return;
      }
      final start = viewport.getOffsetToReveal(box, 0).offset;
      final extent = position.axis == Axis.vertical
          ? box.size.height
          : box.size.width;
      final margin = position.viewportDimension;
      final near =
          start + extent >= position.pixels - margin &&
          start <= position.pixels + position.viewportDimension + margin;
      if (near == _nearViewport) return;
      // Drop a strip from the image cache once it leaves the window so only
      // the strips around the viewport stay decoded.
      if (!near) unawaited(widget.image.evict());
      setState(() => _nearViewport = near);
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    if (_nearViewport) unawaited(widget.image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    if (!_nearViewport) return const SizedBox.expand();
    return Image(
      image: widget.image,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (frame != null || sync) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onFrame();
          });
        }
        return child;
      },
      errorBuilder: (context, error, stack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onFrame();
        });
        return const Center(child: Icon(Icons.broken_image_outlined));
      },
    );
  }
}
