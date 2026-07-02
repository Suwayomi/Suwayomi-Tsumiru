// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'incognito_mode.g.dart';

/// Session-only "incognito" flag. While true, the reader
/// records no reading progress, so nothing enters history and no chapter is
/// marked read.
///
/// Deliberately NOT persisted: it resets to off on app restart. `keepAlive` so it
/// survives having no widget listener — the reader only reads it imperatively.
@Riverpod(keepAlive: true)
class IncognitoMode extends _$IncognitoMode {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}
