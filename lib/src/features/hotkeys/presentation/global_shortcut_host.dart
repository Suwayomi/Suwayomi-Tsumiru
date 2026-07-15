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
import '../../settings/presentation/general/quick_search_toggle/quick_search_toggle_tile.dart';
import '../data/hotkey_binding.dart';

/// App-wide keyboard + mouse navigation, mounted as the OUTERMOST wrapper
/// around the shell. Owns every global shortcut (back, search, library,
/// downloads) so there is a single `Shortcuts` layer that reliably receives
/// keys — the FocusScope below keeps a focused node under it at all times,
/// which a bare `Shortcuts` needs to fire. Esc is routed via Flutter's
/// built-in [DismissIntent] so dialogs/menus dismiss first and this is the
/// last resort.
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
          // Esc: close the quick-open overlay if it's showing, else go back.
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
        // A `Shortcuts` widget only receives key events when a focused widget
        // lives below it. The app shell never autofocuses anything, so without
        // this the whole global keymap is dead. FocusScope(autofocus) keeps a
        // focused node under the host at all times (yielding to any inner
        // widget — text field, reader — that requests focus).
        child: FocusScope(
          autofocus: true,
          child: Builder(
            builder: (context) => Listener(
              // buttons is a bitmask — test the bit, not equality, so a chorded
              // press (e.g. left held + back) still triggers.
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
