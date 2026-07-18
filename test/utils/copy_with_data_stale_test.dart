// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard for stale-while-revalidate: a derived provider built with
// `.copyWithData` must keep showing the mapped previous value while its upstream
// reloads, instead of collapsing to a bare loading (which blanked Sources /
// Extensions / global search to a full-screen spinner on every reload).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

class _Source {
  Completer<int> completer = Completer<int>();
}

class _Trigger extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final _source = _Source();
final _trigger = NotifierProvider<_Trigger, int>(_Trigger.new);
final _upstream = FutureProvider.autoDispose<int>((ref) {
  // Depend on _trigger so bumping it forces a RELOAD (isReloading) — the case
  // skipLoadingOnReload governs, distinct from an invalidate-driven refresh.
  ref.watch(_trigger);
  return _source.completer.future;
});
final _derived = Provider.autoDispose<AsyncValue<String>>(
    (ref) => ref.watch(_upstream).copyWithData((v) => 'mapped:$v'));

void main() {
  test('copyWithData keeps stale mapped data while the upstream reloads', () async {
    _source.completer = Completer<int>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(_derived, (_, __) {});

    // Initial load resolves to 1.
    _source.completer.complete(1);
    await container.read(_upstream.future);
    expect(container.read(_derived).value, 'mapped:1');

    // Reload via a DEPENDENCY change (not invalidate) with a fresh pending fetch.
    _source.completer = Completer<int>();
    container.read(_trigger.notifier).bump();
    await Future<void>.delayed(Duration.zero);

    // DURING the reload the derived value must still expose the stale mapped
    // value — not a bare loading with no value (the bug).
    final duringReload = container.read(_derived);
    expect(duringReload.hasValue, isTrue,
        reason: 'stale value must survive an upstream reload');
    expect(duringReload.value, 'mapped:1');

    // Reload completes with the new value.
    _source.completer.complete(2);
    await container.read(_upstream.future);
    expect(container.read(_derived).value, 'mapped:2');
    sub.close();
  });
}
