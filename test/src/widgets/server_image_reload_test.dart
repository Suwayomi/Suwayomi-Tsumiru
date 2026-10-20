import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

void main() {
  test('an account switch aborts a reload, and a same-session reload tolerates '
      'missing entries', () async {
    // A switch during eviction cannot refresh or remount.
    var current = true;
    var refreshes = 0;
    final evicted = <String>[];
    final released = Completer<void>();
    var pending = reloadServerImage(
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

    // A switch during refresh cannot remount.
    current = true;
    final started = Completer<void>();
    final releasedAgain = Completer<void>();
    pending = reloadServerImage(
      cacheKeys: ['base'],
      isCurrentSession: () => current,
      evict: (_) async {},
      refresh: () async {
        started.complete();
        await releasedAgain.future;
      },
    );
    await started.future;
    current = false;
    releasedAgain.complete();
    expect(await pending, isFalse);

    // A same-session reload survives missing cache entries.
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
