// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:typed_data';

import 'package:tsumiru/src/features/offline/data/background/record_seal.dart';

/// Runs before every test file under test/. The app loads this key at launch
/// and each worker at its entry point; tests serialise background token
/// records without going through either.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RecordSeal.debugKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  await testMain();
}
