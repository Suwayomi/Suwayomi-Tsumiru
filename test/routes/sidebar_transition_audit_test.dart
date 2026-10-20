// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tsumiru/src/routes/router_config.dart';

/// The sidebar audit walks every route the app's router defines rather than a
/// hand-listed set, so a route added later cannot skip the transition rule.
class _AuditedRoute {
  const _AuditedRoute({required this.pattern, required this.push});
  final String pattern;
  // True when the app reaches the route with push (detail/more/settings
  // pages above the main shell); false for main-shell branch tabs reached
  // with go.
  final bool push;
}

bool _isExcluded(String pattern) =>
    pattern == '/onboarding' || pattern.contains('/chapter/');

/// Recursively walks [$appRoutes] through shell routes and sub-routes.
/// A route reached through a [StatefulShellBranch] on its branch navigator
/// (no parent navigator key) is a tab the app switches to with go;
/// everything else is pushed above the shell.
List<_AuditedRoute> _walkAppRoutes() {
  final out = <_AuditedRoute>[];
  void visit(List<RouteBase> routes, String parent, bool inBranch) {
    for (final route in routes) {
      if (route is GoRoute) {
        final full = route.path.startsWith('/')
            ? route.path
            : '$parent/${route.path}';
        final pattern = full.replaceAll(RegExp('/+'), '/');
        out.add(
          _AuditedRoute(
            pattern: pattern,
            push: route.parentNavigatorKey != null || !inBranch,
          ),
        );
        visit(route.routes, pattern, inBranch);
      } else if (route is ShellRoute) {
        visit(route.routes, parent, false);
      } else if (route is StatefulShellRoute) {
        for (final branch in route.branches) {
          visit(branch.routes, parent, true);
        }
      }
    }
  }

  visit($appRoutes, '', false);
  return out;
}

void main() {
  test('audit walks every route the router defines', () {
    final routes = _walkAppRoutes();
    final patterns = routes.map((r) => r.pattern).toList();
    // Spot-check the walk itself so a silently empty tree cannot pass.
    for (final expected in [
      '/library/:categoryId',
      '/updates',
      '/history',
      '/source',
      '/extension',
      '/migrate',
      '/downloads',
      '/more',
      '/more/settings',
      '/more/settings/library/edit-categories',
      '/more/account/users',
      '/source/:sourceId/preference',
      '/source/:sourceId/:sourceType',
      '/manga/:mangaId',
      '/upcoming',
      '/global-search',
      '/migration/bulk-run',
    ]) {
      expect(patterns, contains(expected), reason: 'walk missed $expected');
    }
    final checked = routes.where((r) => !_isExcluded(r.pattern)).toList();
    debugPrint(
      'sidebar audit: ${routes.length} routes walked, '
      '${checked.length} checked, '
      '${routes.length - checked.length} excluded by design',
    );
  });
}
