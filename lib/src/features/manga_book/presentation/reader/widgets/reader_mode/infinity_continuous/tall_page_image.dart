import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:image/image.dart' as img;

import 'measure_size.dart';

const _stripChannel = MethodChannel('tsumiru/page_strips');
int _nextStripOwner = 0;

Future<ui.Size> tallPageIntrinsicSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(path).readAsBytes(),
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

class _StripPixels {
  const _StripPixels(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

List<_StripPixels> _cutStrips((String, int) request) {
  final decoded = img.decodeImage(File(request.$1).readAsBytesSync());
  if (decoded == null) throw StateError('Cannot decode page');
  return [
    for (var y = 0; y < decoded.height; y += request.$2)
      _StripPixels(
        img.copyCrop(
          decoded,
          x: 0,
          y: y,
          width: decoded.width,
          height: math.min(request.$2, decoded.height - y),
        ).getBytes(order: img.ChannelOrder.rgba),
        decoded.width,
        math.min(request.$2, decoded.height - y),
      ),
  ];
}

class _TallPageSource {
  _TallPageSource(this.path, this.cacheKey, this.size, int limit)
    : stripHeight = math.min(limit, 4096);

  final String path;
  final String cacheKey;
  final ui.Size size;
  final int stripHeight;
  final String owner = '${_nextStripOwner++}';
  Future<List<_StripPixels>>? _fallback;
  final _decodedStrips = <int>{};
  bool _nativeFailed = false;
  bool _disposed = false;

  int get count => (size.height / stripHeight).ceil();
  int heightAt(int index) => math.min(
    stripHeight,
    size.height.toInt() - index * stripHeight,
  );

  Future<_StripPixels> pixels(int index) async {
    if (_disposed) throw StateError('Page has been released');
    if (defaultTargetPlatform == TargetPlatform.android && !_nativeFailed) {
      try {
        final result = await _stripChannel.invokeMapMethod<String, dynamic>(
          'decodeStrip',
          {
            'path': path,
            'owner': owner,
            'top': index * stripHeight,
            'height': heightAt(index),
          },
        );
        final pixels = _StripPixels(
          result!['rgba'] as Uint8List,
          result['width'] as int,
          result['height'] as int,
        );
        if (pixels.width != size.width ||
            pixels.height != heightAt(index) ||
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
    final strips = await (_fallback ??= compute(_cutStrips, (path, stripHeight)));
    return strips[index];
  }

  void _releaseNative() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(
      _stripChannel.invokeMethod<void>('release', {
        'path': path,
        'owner': owner,
      }).catchError((Object _) {}),
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
      index == other.index;

  @override
  int get hashCode => Object.hash(source.cacheKey, index, source.stripHeight);
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
  final int limit;
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
      final size = await tallPageIntrinsicSize(path);
      return size.height > limit
          ? _TallPageSource(path, cacheKey, size, limit)
          : null;
    }, [cacheKey, limit]);
    useEffect(() {
      return () {
        unawaited(
          future.then((source) => source?.dispose()).catchError((Object _) {}),
        );
      };
    }, [future]);
    final snapshot = useFuture(future);
    final ready = useState(false);
    useEffect(() {
      ready.value = false;
      return null;
    }, [future]);
    if (snapshot.connectionState != ConnectionState.done) return placeholder;
    final source = snapshot.data;
    if (source == null) return fallback;
    final width = horizontal
        ? (naturalSize ? math.min(crossAxisExtent, source.size.height)
            : crossAxisExtent) * source.size.width / source.size.height
        : naturalSize
            ? math.min(crossAxisExtent, source.size.width)
            : crossAxisExtent;
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
      if (box is! RenderBox || !box.hasSize ||
          viewport == null || position == null) {
        return;
      }
      final start = viewport.getOffsetToReveal(box, 0).offset;
      final extent = position.axis == Axis.vertical
          ? box.size.height : box.size.width;
      final margin = position.viewportDimension;
      final near = start + extent >= position.pixels - margin &&
          start <= position.pixels + position.viewportDimension + margin;
      if (near != _nearViewport) setState(() => _nearViewport = near);
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
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
