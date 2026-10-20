// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/network/paginate.dart';

// Specification of collectAllPages — the completeness guard that stops a
// truncated library fetch from driving the offline prune (which stamps '0' and
// deletes rows absent from the list). The rule: return every node in order when
// the result is provably complete, otherwise null. Never a short list.
void main() {
  // Builds a fetchPage that serves [pages] in order, matching the requested
  // cursor, and records every cursor it was asked for.
  ({Future<PaginatedPage<int>?> Function(int?) fetch, List<int?> cursors})
  pager(List<PaginatedPage<int>?> pages) {
    final cursors = <int?>[];
    var i = 0;
    Future<PaginatedPage<int>?> fetch(int? after) async {
      cursors.add(after);
      return pages[i++];
    }

    return (fetch: fetch, cursors: cursors);
  }

  test('concatenates pages in cursor order and checks the total', () async {
    final single = pager([
      (nodes: [1, 2, 3], hasNextPage: false, endCursor: null, totalCount: 3),
    ]);
    expect(await collectAllPages<int>(single.fetch), [1, 2, 3]);
    expect(single.cursors, [null]); // one call, no cursor

    final many = pager([
      (nodes: [1, 2], hasNextPage: true, endCursor: 20, totalCount: 5),
      (nodes: [3, 4], hasNextPage: true, endCursor: 40, totalCount: 5),
      (nodes: [5], hasNextPage: false, endCursor: null, totalCount: 5),
    ]);
    expect(await collectAllPages<int>(many.fetch), [1, 2, 3, 4, 5]);
    // First call unanchored, then each follows the previous endCursor.
    expect(many.cursors, [null, 20, 40]);

    // An assembled count that matches totalCount passes.
    final counted = pager([
      (nodes: [1, 2, 3], hasNextPage: true, endCursor: 30, totalCount: 4),
      (nodes: [4], hasNextPage: false, endCursor: null, totalCount: 4),
    ]);
    expect(await collectAllPages<int>(counted.fetch), [1, 2, 3, 4]);
  });

  test('a failed page (null) aborts to null — never a partial list', () async {
    final p = pager([
      (nodes: [1, 2], hasNextPage: true, endCursor: 20, totalCount: 5),
      null, // transient failure mid-pagination
    ]);
    expect(await collectAllPages<int>(p.fetch), isNull);
  });

  test('a truncated response returns null, never a short list', () async {
    // Server claims 5 but stops advertising more after 3.
    final truncated = pager([
      (nodes: [1, 2, 3], hasNextPage: false, endCursor: null, totalCount: 5),
    ]);
    expect(await collectAllPages<int>(truncated.fetch), isNull);

    // hasNextPage true but a null cursor stops, and the count mismatch makes
    // it null rather than a short list.
    final nullCursor = pager([
      (nodes: [1, 2], hasNextPage: true, endCursor: null, totalCount: 5),
    ]);
    expect(await collectAllPages<int>(nullCursor.fetch), isNull);
  });

  test('an empty but complete library (totalCount 0) returns an empty list, '
      'not null', () async {
    final p = pager([
      (nodes: <int>[], hasNextPage: false, endCursor: null, totalCount: 0),
    ]);
    expect(await collectAllPages<int>(p.fetch), isEmpty);
  });
}
