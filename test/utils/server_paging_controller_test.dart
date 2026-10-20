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

      // A non-empty last page ends the list without an extra request.
      controller.fetchNextPage();
      await pumpEventQueue();
      expect(requested, [1, 2, 3]);
    });
  });
}
