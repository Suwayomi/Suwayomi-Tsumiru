import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/source_page_sequence.dart';
import 'package:tsumiru/src/utils/hooks/paging_controller_hook.dart';

void main() {
  test('obsolete hidden pages cannot change refreshed pagination', () async {
    final sequence = SourcePageSequence<int>();
    final blocked = Completer<ServerPage<int>>();
    final oldPages = <int>[];
    final old = sequence.fetch(1, (page) async {
      oldPages.add(page);
      if (page == 1) return (items: <int>[], hasNextPage: true);
      return blocked.future;
    });
    await Future<void>.delayed(Duration.zero);
    sequence.refresh();
    await sequence.fetch(1, (_) async => (items: [10], hasNextPage: true));
    blocked.complete((items: <int>[], hasNextPage: true));
    await old;
    int? requested;
    final page = await sequence.fetch(2, (sourcePage) async {
      requested = sourcePage;
      return (items: [20], hasNextPage: false);
    });
    expect(oldPages, [1, 2]);
    expect(requested, 2);
    expect(page.items, [20]);
  });
}
