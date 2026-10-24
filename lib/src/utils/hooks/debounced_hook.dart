// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';

/// Starts at value, then holds the last settled value until changes stop for delay.
T useSettled<T>(T value, Duration delay) {
  final settled = useState<T>(value);
  useEffect(() {
    if (value == settled.value) return null;
    final timer = Timer(delay, () => settled.value = value);
    return timer.cancel;
  }, [value]);
  return settled.value;
}
