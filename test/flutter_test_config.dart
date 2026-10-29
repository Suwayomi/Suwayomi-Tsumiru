// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tsumiru/src/features/offline/data/background/record_seal.dart';

class _SupportFallback extends PathProviderPlatform {
  _SupportFallback(this.previous, this.support);
  final PathProviderPlatform previous;
  final String support;
  @override
  Future<String?> getApplicationSupportPath() async {
    try {
      return await previous.getApplicationSupportPath() ?? support;
    } on MissingPluginException {
      return support;
    } on FlutterError {
      return support;
    } on UnimplementedError {
      return support;
    }
  }

  @override
  Future<String?> getTemporaryPath() => previous.getTemporaryPath();
  @override
  Future<String?> getLibraryPath() => previous.getLibraryPath();
  @override
  Future<String?> getApplicationDocumentsPath() =>
      previous.getApplicationDocumentsPath();
  @override
  Future<String?> getApplicationCachePath() =>
      previous.getApplicationCachePath();
  @override
  Future<String?> getExternalStoragePath() => previous.getExternalStoragePath();
  @override
  Future<List<String>?> getExternalCachePaths() =>
      previous.getExternalCachePaths();
  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) =>
      previous.getExternalStoragePaths(type: type);
  @override
  Future<String?> getDownloadsPath() => previous.getDownloadsPath();
}

/// Runs before every test file under test/. The app loads this key at launch
/// and each worker at its entry point; tests serialise background token
/// records without going through either.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RecordSeal.debugKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  if (!kIsWeb) await _installSupportFallback();
  await testMain();
}

Future<void> _installSupportFallback() async {
  final previous = PathProviderPlatform.instance;
  final support = await Directory.systemTemp.createTemp(
    'tsumiru-test-support-',
  );
  PathProviderPlatform.instance = _SupportFallback(previous, support.path);
}
