// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../quick_open/presentation/search_stack/search_stack_screen.dart';
import '../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../settings/presentation/general/quick_search_toggle/quick_search_toggle_tile.dart';
import '../data/hotkey_binding.dart';

/// Hidden shell branches stay mounted; exclude their search fields to avoid stealing focus.
bool desktopSearchNodeIsCurrent(FocusNode node) {
  final context = node.context;
  if (context == null) return false;
  // Hidden keep-alive branches (IndexedStack/Offstage) disable tickers.
  if (!TickerMode.valuesOf(context).enabled) return false;
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return false;
  return true;
}

/// Must wrap the shell with a focused descendant for Shortcuts to receive keys.
/// DismissIntent lets dialogs and menus handle Escape before global navigation.
class GlobalShortcutHost extends ConsumerWidget {
  const GlobalShortcutHost({super.key, required this.child});

  final Widget child;

  void _back(BuildContext context) {
    if (GoRouter.of(context).canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openSearch() {
      if (ref.read(quickSearchToggleProvider).ifNull()) {
        // Skip detached or hidden-branch search fields; fall back to the overlay.
        final field = ref.read(desktopSearchFocusNodeProvider);
        if (field != null && desktopSearchNodeIsCurrent(field)) {
          field.requestFocus();
          return;
        }
        ref.read(unifiedSearchQueryProvider.notifier).state = '';
        ref.read(quickOpenVisibleProvider.notifier).state = true;
      }
    }

    return Shortcuts(
      shortcuts: {
        for (final h in activeGlobalHotkeys())
          if (h.hasKeyboardActivator) h.activator: h.intent,
      },
      child: Actions(
        actions: {
          EscapeIntent: CallbackAction<EscapeIntent>(
            onInvoke: (_) {
              if (ref.read(quickOpenVisibleProvider)) {
                ref.read(quickOpenVisibleProvider.notifier).state = false;
              } else {
                _back(context);
              }
              return null;
            },
          ),
          GoBackIntent: CallbackAction<GoBackIntent>(
            onInvoke: (_) {
              _back(context);
              return null;
            },
          ),
          OpenSearchIntent: CallbackAction<OpenSearchIntent>(
            onInvoke: (_) {
              openSearch();
              return null;
            },
          ),
          OpenLibraryIntent: CallbackAction<OpenLibraryIntent>(
            onInvoke: (_) {
              const LibraryRoute(categoryId: 0).go(context);
              return null;
            },
          ),
          OpenDownloadsIntent: CallbackAction<OpenDownloadsIntent>(
            onInvoke: (_) {
              const DownloadsRoute().go(context);
              return null;
            },
          ),
        },
        // Shortcuts needs a focused descendant; this scope yields to inner fields and readers.
        child: FocusScope(
          autofocus: true,
          child: Builder(
            builder: (context) => Listener(
              // Test the bitmask so back still works when another mouse button is held.
              onPointerDown: (event) {
                if (event.buttons & kBackMouseButton != 0) {
                  Actions.maybeInvoke(context, const GoBackIntent());
                }
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
