// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Useful to log state change in our application
/// Read the logs and you'll better understand what's going on under the hood
final class ProviderStateLogger extends ProviderObserver {
  const ProviderStateLogger();
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    debugPrint('''
{
  provider: ${context.provider.name ?? context.provider.runtimeType},
  oldValue: $previousValue,
  newValue: $newValue
}
''');
    super.didUpdateProvider(context, previousValue, newValue);
  }
}
