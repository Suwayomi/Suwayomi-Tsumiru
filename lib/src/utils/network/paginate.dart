// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// totalCount is the whole result count, not the count of this page.
typedef PaginatedPage<T> = ({
  List<T> nodes,
  bool hasNextPage,
  int? endCursor,
  int totalCount,
});

/// Fetch in order from a null cursor; null means incomplete and must never drive destructive reconciliation.
Future<List<T>?> collectAllPages<T>(
  Future<PaginatedPage<T>?> Function(int? after) fetchPage,
) async {
  final all = <T>[];
  int? after;
  int? totalCount;
  while (true) {
    final page = await fetchPage(after);
    if (page == null) return null; // a failed page => not provably complete
    all.addAll(page.nodes);
    totalCount ??= page.totalCount;
    if (!page.hasNextPage || page.endCursor == null) break;
    after = page.endCursor;
  }
  // Missing totalCount must count as incomplete.
  return all.length == totalCount ? all : null;
}
