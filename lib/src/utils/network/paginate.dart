// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// One page of a cursor-paginated server list. [totalCount] is the server's
/// count of the WHOLE result (Suwayomi's `*NodeList.totalCount`), used to prove
/// the assembled result is complete.
typedef PaginatedPage<T> = ({
  List<T> nodes,
  bool hasNextPage,
  int? endCursor,
  int totalCount,
});

/// Walk a cursor-paginated list to exhaustion via [fetchPage] (called with the
/// previous page's cursor, null for the first), returning every node in order.
///
/// Returns null — never a short list — when the result is not provably
/// complete: a page fetch failed ([fetchPage] returned null), or the assembled
/// node count doesn't match the server's [PaginatedPage.totalCount]. Callers
/// that drive destructive reconciliation from a library list (e.g. an offline
/// prune that deletes rows absent from the fetch) MUST treat null as "no usable
/// answer" and skip, so a truncated page can never masquerade as a shrunken
/// library.
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
  // `== totalCount` (not `!= null && ...`) so a null count degrades to
  // "incomplete" instead of silently passing.
  return all.length == totalCount ? all : null;
}
