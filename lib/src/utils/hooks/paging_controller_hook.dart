// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

/// One page as the server reports it: its items, and whether another follows.
typedef ServerPage<ItemType> = ({List<ItemType> items, bool hasNextPage});

/// A [PagingController] for integer-keyed APIs that say whether another page
/// follows alongside each page, instead of ending with an empty page.
///
/// [PagingController] only learns a list is over when `getNextPageKey`
/// returns null, so the last page's flag is kept here for it. A reply that
/// lands after a [refresh] belongs to the previous list: the controller drops
/// its items, and the epoch check keeps its flag from ending the new list.
class ServerPagingController<ItemType> extends PagingController<int, ItemType> {
  factory ServerPagingController({
    required int firstPageKey,
    required Future<ServerPage<ItemType>> Function(int pageKey) fetchPage,
  }) =>
      ServerPagingController._(
        _PageFlag(),
        firstPageKey: firstPageKey,
        fetchPage: fetchPage,
      );

  ServerPagingController._(
    this._flag, {
    required int firstPageKey,
    required Future<ServerPage<ItemType>> Function(int pageKey) fetchPage,
  }) : super(
          getNextPageKey: (state) {
            final lastKey = state.keys?.lastOrNull;
            if (lastKey == null) return firstPageKey;
            return _flag.hasNextPage ? lastKey + 1 : null;
          },
          fetchPage: (pageKey) async {
            final epoch = _flag.epoch;
            final page = await fetchPage(pageKey);
            if (epoch == _flag.epoch) _flag.hasNextPage = page.hasNextPage;
            return page.items;
          },
        );

  final _PageFlag _flag;

  @override
  void refresh() {
    _flag
      ..epoch += 1
      ..hasNextPage = true;
    super.refresh();
  }
}

class _PageFlag {
  int epoch = 0;
  bool hasNextPage = true;
}

/// Creates a [ServerPagingController] that will be disposed automatically.
///
/// [fetchPage] is captured once, on the first build: read anything that
/// changes between builds through a ref.
ServerPagingController<ItemType> useServerPagingController<ItemType>({
  required int firstPageKey,
  required Future<ServerPage<ItemType>> Function(int pageKey) fetchPage,
}) {
  final controller = useMemoized(
    () => ServerPagingController<ItemType>(
      firstPageKey: firstPageKey,
      fetchPage: fetchPage,
    ),
  );
  useEffect(() => controller.dispose, [controller]);
  return controller;
}
