// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// C ABI declared in `linux/tsumiru_avif.h`.
typedef _ToPngNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.IntPtr>,
    );
typedef _ToPngDart =
    int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ffi.Pointer<ffi.IntPtr>,
    );
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8>);

const _libraryName = 'libtsumiru_avif.so';

/// 64 MP of straight RGBA plus PNG overhead; anything larger is a bad result.
const _maxPngBytes = 512 * 1024 * 1024;

/// Thin Linux bridge to the bundled libavif shim. Never throws to callers.
final class AvifNative {
  AvifNative._(this._toPng, this._free);

  static AvifNative? _instance;
  static bool _unavailable = false;

  static AvifNative? get instance {
    final cached = _instance;
    if (cached != null) return cached;
    if (_unavailable || !Platform.isLinux) return null;
    try {
      final library = _openLibrary();
      _instance = AvifNative._(
        library.lookupFunction<_ToPngNative, _ToPngDart>('tsumiru_avif_to_png'),
        library.lookupFunction<_FreeNative, _FreeDart>('tsumiru_avif_free'),
      );
    } catch (_) {
      _unavailable = true;
    }
    return _instance;
  }

  final _ToPngDart _toPng;
  final _FreeDart _free;

  /// Returns PNG bytes, or null when the shim is missing or rejects the input.
  Uint8List? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final input = calloc<ffi.Uint8>(bytes.length);
    final output = calloc<ffi.Pointer<ffi.Uint8>>();
    final outputLength = calloc<ffi.IntPtr>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final status = _toPng(input, bytes.length, output, outputLength);
      final pointer = output.value;
      final length = outputLength.value;
      if (status != 0) {
        if (pointer != ffi.nullptr) _free(pointer);
        return null;
      }
      if (pointer == ffi.nullptr || length <= 0 || length > _maxPngBytes) {
        if (pointer != ffi.nullptr) _free(pointer);
        return null;
      }
      try {
        return Uint8List.fromList(pointer.asTypedList(length));
      } finally {
        _free(pointer);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(outputLength);
      calloc.free(output);
      calloc.free(input);
    }
  }
}

ffi.DynamicLibrary _openLibrary() {
  Object? lastError;
  for (final candidate in _libraryCandidates()) {
    try {
      return ffi.DynamicLibrary.open(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('$_libraryName unavailable: $lastError');
}

Iterable<String> _libraryCandidates() sync* {
  final bundle = p.dirname(Platform.resolvedExecutable);
  yield p.join(bundle, 'lib', _libraryName);
  yield p.join(bundle, _libraryName);
  // Flatpak and test runs can place the soname on the loader path.
  yield _libraryName;
}
