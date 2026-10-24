// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_state.g.dart';

@Riverpod(keepAlive: true)
class NeedsReauth extends _$NeedsReauth {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
