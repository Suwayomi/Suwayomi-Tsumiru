// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'incognito_mode.g.dart';

/// Suppresses progress, history and read markers until app restart.
/// Keep alive because the reader reads it without a widget listener.
@Riverpod(keepAlive: true)
class IncognitoMode extends _$IncognitoMode {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}
