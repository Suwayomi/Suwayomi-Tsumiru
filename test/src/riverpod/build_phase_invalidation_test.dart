// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pins the Riverpod 3 behavior behind the refresh-on-mount deferrals in
/// manga details, sources, extensions, and the library category list:
/// flutter_hooks runs effect bodies during build, and invalidating a provider
/// there throws "setState() or markNeedsBuild() called during build". If the
/// sync case stops throwing after a riverpod upgrade, the microtask
/// workarounds at those sites can be dropped.
final _tickProvider = NotifierProvider<_TickNotifier, int>(_TickNotifier.new);

class _TickNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => ref.invalidateSelf();
}

class _RefreshOnMount extends HookConsumerWidget {
  const _RefreshOnMount({required this.defer});
  final bool defer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(_tickProvider);
    useEffect(() {
      if (defer) {
        Future.microtask(() => ref.read(_tickProvider.notifier).refresh());
      } else {
        ref.read(_tickProvider.notifier).refresh();
      }
      return null;
    }, const []);
    return Text('$v', textDirection: TextDirection.ltr);
  }
}

void main() {
  testWidgets('invalidating during build throws', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _RefreshOnMount(defer: false)),
    );
    final e = tester.takeException();
    expect('$e', contains('called during build'));
  });

  testWidgets('microtask-deferred invalidation is clean', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _RefreshOnMount(defer: true)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
