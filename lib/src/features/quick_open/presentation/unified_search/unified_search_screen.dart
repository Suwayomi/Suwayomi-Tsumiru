// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/search_field.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_providers.dart';
import 'unified_search_results.dart';

/// Up/Down move the results highlight; focus stays in the field.
class _MoveSearchHighlightIntent extends Intent {
  const _MoveSearchHighlightIntent(this.delta);

  /// +1 for Down, -1 for Up.
  final int delta;
}

class _MoveSearchHighlightAction extends Action<_MoveSearchHighlightIntent> {
  _MoveSearchHighlightAction({required this.onInvoke});

  final void Function(int delta) onInvoke;

  @override
  Object? invoke(_MoveSearchHighlightIntent intent) {
    onInvoke(intent.delta);
    return null;
  }
}

class UnifiedSearchScreen extends HookConsumerWidget {
  const UnifiedSearchScreen({super.key, required this.afterClick});

  final VoidCallback afterClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;

    // DslSearchController highlights recognized operators, same as the library
    // bar; we own it (not onChanged) so applying a suggestion can splice text.
    final controller = useMemoized(
      () => DslSearchController(text: ref.read(unifiedSearchQueryProvider)),
      const [],
    );
    final focusNode = useFocusNode();
    final selection = useMemoized(UnifiedSearchSelection.new);
    useEffect(() => selection.dispose, [selection]);
    useEffect(() {
      var lastText = controller.text;
      void sync() {
        // Only mirror real text edits into the provider. Selection/caret-only
        // changes (e.g. a layout-driven selection clamp) must NOT write state —
        // that could land mid-build and throw. Text only changes from user
        // input or our own setQuery, never during build.
        if (controller.text == lastText) return;
        lastText = controller.text;
        // Every text change clears the highlight; the user moves again from
        // the top.
        selection.reset();
        ref.read(unifiedSearchQueryProvider.notifier).state = controller.text;
      }

      controller.addListener(sync);
      return () {
        controller.removeListener(sync);
        controller.dispose();
      };
    }, const []);
    useListenable(controller); // rebuild on text OR caret move

    final query = ref.watch(unifiedSearchQueryProvider);

    final caretRaw = controller.selection.baseOffset;
    final caret = caretRaw < 0 ? controller.text.length : caretRaw;
    final token = activeTokenAt(controller.text, caret);

    void close() => afterClick();

    void setQuery(String text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      focusNode.requestFocus();
    }

    void applyAndStay(SearchSuggestion s) {
      final edit = applySuggestion(controller.text, token, s);
      setQuery(edit.text);
      controller.selection = TextSelection.collapsed(offset: edit.caret);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        // Absorb taps on the card's blank areas so a near-miss doesn't fall
        // through to the overlay's outer close-on-tap.
        child: GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            // Hug content, but cap the height so a long result set scrolls
            // inside a tidy panel instead of running to the screen edge.
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: Material(
              color: context.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            _MoveSearchHighlightIntent(1),
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            _MoveSearchHighlightIntent(-1),
                      },
                      child: Actions(
                        actions: {
                          _MoveSearchHighlightIntent:
                              _MoveSearchHighlightAction(
                                onInvoke: (delta) {
                                  if (delta > 0) {
                                    selection.moveDown();
                                  } else {
                                    selection.moveUp();
                                  }
                                },
                              ),
                        },
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: l.unifiedSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: InputBorder.none,
                          ),
                          // Enter opens the highlighted row exactly as a tap
                          // would; with no highlight, the top result — shared
                          // with the desktop dropdowns so it behaves one way
                          // everywhere.
                          onSubmitted: (_) {
                            if (selection.activateSelected()) return;
                            submitUnifiedQuery(
                              context,
                              ref,
                              query,
                              includeLibrary: true,
                              close: close,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: UnifiedSearchResults(
                      query: query,
                      close: close,
                      caret: caret,
                      onSetQuery: setQuery,
                      onApplySuggestion: applyAndStay,
                      selection: selection,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
