import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

void main() {
  test('account switch during eviction cannot refresh or remount', () async {
    var current = true;
    var refreshes = 0;
    final evicted = <String>[];
    final released = Completer<void>();
    final pending = reloadServerImage(
      cacheKeys: ['base', 'fetch'],
      isCurrentSession: () => current,
      evict: (key) async {
        evicted.add(key);
        await released.future;
      },
      refresh: () async {
        refreshes++;
      },
    );
    await pumpEventQueue();
    current = false;
    released.complete();
    expect(await pending, isFalse);
    expect(evicted, ['base']);
    expect(refreshes, 0);
  });

  test('account switch during refresh cannot remount', () async {
    var current = true;
    final started = Completer<void>();
    final released = Completer<void>();
    final pending = reloadServerImage(
      cacheKeys: ['base'],
      isCurrentSession: () => current,
      evict: (_) async {},
      refresh: () async {
        started.complete();
        await released.future;
      },
    );
    await started.future;
    current = false;
    released.complete();
    expect(await pending, isFalse);
  });

  test('same-session reload tolerates missing cache entries', () async {
    var refreshes = 0;
    expect(
      await reloadServerImage(
        cacheKeys: ['base'],
        isCurrentSession: () => true,
        evict: (_) async {
          throw StateError('missing');
        },
        refresh: () async {
          refreshes++;
        },
      ),
      isTrue,
    );
    expect(refreshes, 1);
  });
}
