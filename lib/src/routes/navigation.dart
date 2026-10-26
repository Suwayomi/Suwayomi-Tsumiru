// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'router_config.dart';

/// A detail page pushed over the reader would stack a second detail shell.
Future<T?> pushDetailPage<T extends Object?>(
  BuildContext context,
  String location,
) {
  final router = GoRouter.of(context);
  final overReader =
      router.routerDelegate.currentConfiguration.last.route.path ==
      Routes.reader;
  return overReader
      ? router.pushReplacement<T>(location)
      : router.push<T>(location);
}

/// Push global search so replacing the stack cannot discard its return route.
void openGlobalSearch(
  BuildContext context, {
  String? query,
  bool fromSuggestion = false,
}) => pushDetailPage(
  context,
  GlobalSearchRoute(query: query, fromSuggestion: fromSuggestion).location,
);
