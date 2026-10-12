import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:tsumiru/src/utils/hooks/paging_controller_hook.dart';

void main() {
  group('ServerPagingController', () {
    test('keeps fetching while the server reports another page', () async {
      final requested = <int>[];
      final controller = ServerPagingController<int>(
        firstPageKey: 1,
        fetchPage: (key) async {
          requested.add(key);
          return (items: [key], hasNextPage: key < 3);
        },
      );
      addTearDown(controller.dispose);

      for (var i = 0; i < 5; i++) {
        controller.fetchNextPage();
        await pumpEventQueue();
      }

      expect(requested, [1, 2, 3]);
      expect(controller.items, [1, 2, 3]);
      expect(controller.hasNextPage, isFalse);
    });

    test('ends on a non-empty last page without an extra request', () async {
      var calls = 0;
      final controller = ServerPagingController<int>(
        firstPageKey: 0,
        fetchPage: (key) async {
          calls++;
          return (items: [1, 2], hasNextPage: false);
        },
      );
      addTearDown(controller.dispose);

      controller.fetchNextPage();
      await pumpEventQueue();
      controller.fetchNextPage();
      await pumpEventQueue();

      expect(calls, 1);
      expect(controller.hasNextPage, isFalse);
    });

    test('a reply landing after refresh neither shows nor ends the new list',
        () async {
      final pending = <int, Completer<ServerPage<String>>>{};
      final controller = ServerPagingController<String>(
        firstPageKey: 0,
        fetchPage: (key) => (pending[key] = Completer()).future,
      );
      addTearDown(controller.dispose);

      controller.fetchNextPage();
      final stale = pending[0]!;
      controller.refresh();
      controller.fetchNextPage();
      final fresh = pending[0]!;
      expect(identical(stale, fresh), isFalse);

      fresh.complete((items: ['new'], hasNextPage: true));
      await pumpEventQueue();
      // The old list's last page says "no more", arriving late.
      stale.complete((items: ['old'], hasNextPage: false));
      await pumpEventQueue();

      expect(controller.items, ['new']);
      controller.fetchNextPage();
      await pumpEventQueue();
      expect(pending.keys, contains(1));
    });

    test('shows a fetch exception as the error state', () async {
      final controller = ServerPagingController<int>(
        firstPageKey: 0,
        fetchPage: (_) async => throw Exception('offline'),
      );
      addTearDown(controller.dispose);

      controller.fetchNextPage();
      await pumpEventQueue();

      expect(controller.error, isA<Exception>());
      expect(controller.status, PagingStatus.firstPageError);
    });
  });
}
