// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';

/// Returns [value], but only propagates a change after [value] has stayed the
/// same for [delay]. Initialized to the first [value] (unlike flutter_hooks'
/// `useDebounced`, which starts null). While [value] keeps changing (e.g.
/// dragging a desktop window resize), it holds the previous settled value — so a
/// consumer keyed on it (like an image's decode resolution) doesn't churn every
/// frame.
T useSettled<T>(T value, Duration delay) {
  final settled = useState<T>(value);
  useEffect(() {
    if (value == settled.value) return null;
    final timer = Timer(delay, () => settled.value = value);
    return timer.cancel;
  }, [value]);
  return settled.value;
}
