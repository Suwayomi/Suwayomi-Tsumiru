// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/search_field.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_facets.dart';
import 'unified_search_providers.dart';
import 'unified_search_results.dart';

/// Focus node of the desktop search field currently in the tree, if any.
/// Ctrl+F / Ctrl+P focuses it instead of opening the quick-open overlay; routes
/// without a field (reader, series page) leave this null and keep the overlay.
final desktopSearchFocusNodeProvider = StateProvider<FocusNode?>(
  (Ref ref) => null,
);

class _CloseSearchDropdownIntent extends Intent {
  const _CloseSearchDropdownIntent();
}

/// Esc handler that is only enabled while there is something to do (an open
/// dropdown or text to clear). Disabled, the key event is ignored by this
/// layer and keeps propagating to the global Esc=Back handler.
class _CloseSearchDropdownAction extends Action<_CloseSearchDropdownIntent> {
  _CloseSearchDropdownAction({required this.isActive, required this.onInvoke});

  final bool Function() isActive;
  final void Function() onInvoke;

  @override
  bool get isActionEnabled => isActive();

  @override
  Object? invoke(_CloseSearchDropdownIntent intent) {
    onInvoke();
    return null;
  }
}

/// Visible search box for desktop pages, in the same top-left place on every
/// page. 40 px tall, radius 10, same box style as the Library toolbar's
/// DesktopToolbarBox. Typing opens a dropdown anchored directly under the
/// field showing the unified results; Esc or clicking outside closes it, Esc
/// again clears the text.
class DesktopSearchField extends HookConsumerWidget {
  const DesktopSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.onNavigate,
    this.leading = const <Widget>[],
    this.hasLeadingResults = false,
    this.showLibrarySection = true,
    this.hintText,
    this.suffixActions = const <Widget>[],
    this.autofocus = false,
    this.onSubmitLeading,
  });

  /// Current field text, owned by the host (a query provider).
  final String query;

  /// Called on every edit so the host can update its query (and live-filter).
  final ValueChanged<String> onChanged;

  /// Called after leaving through a dropdown result, so the host clears the
  /// query (opening a series from the Library grid keeps it — that path never
  /// touches this).
  final VoidCallback? onNavigate;

  /// Extra result sections before the unified ones (History on its page).
  final List<Widget> leading;

  /// Whether [leading] currently holds matches (drives dropdown visibility).
  final bool hasLeadingResults;

  /// False hides the Library section (the Library grid is already filtered).
  final bool showLibrarySection;

  /// Placeholder; null uses the unified hint.
  final String? hintText;

  /// Extra icon buttons before the clear button (Library: tips + global).
  final List<Widget> suffixActions;

  final bool autofocus;

  /// Enter handler for extra leading sections: navigate to the top leading
  /// result and return true. The field then closes the dropdown and clears
  /// the host query, like any other dropdown result. Null (or false) falls
  /// back to the unified top result.
  final bool Function()? onSubmitLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final controller = useMemoized(() => DslSearchController(text: query));
    useEffect(() => controller.dispose, [controller]);
    // A programmatic change (clearing after navigation, a tag-set query)
    // refreshes the field; while typing both sides already agree. Post-frame:
    // writing the controller mid-build could notify during layout.
    useEffect(() {
      if (controller.text != query) controller.text = query;
      return null;
    }, [query]);
    useListenable(controller); // rebuild on text OR caret move

    final focusNode = useFocusNode();
    final link = useMemoized(LayerLink.new);
    final portal = useMemoized(OverlayPortalController.new);
    final targetKey = useMemoized(GlobalKey.new);
    final fieldWidth = useState<double?>(null);
    final hovered = useState(false);

    void measure() {
      if (!context.mounted) return;
      final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && fieldWidth.value != box.size.width) {
        fieldWidth.value = box.size.width;
      }
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) => measure());
      return null;
    });

    bool canShow(String text, [int? caret]) {
      if (text.trim().isEmpty || fieldWidth.value == null) return false;
      if (hasLeadingResults) return true;
      // Operator autocomplete (the Filters section) can be the only thing a
      // query offers, e.g. `unread:` has no plain text or matches.
      final caretOffset = (caret ?? text.length).clamp(0, text.length);
      if (suggestFor(
        activeTokenAt(text, caretOffset),
        ref.read(unifiedLibraryFacetsProvider),
      ).isNotEmpty) {
        return true;
      }
      // Search all sources is always offered for plain text, so any of it
      // opens the dropdown.
      if (plainQueryText(text).isNotEmpty) return true;
      if (showLibrarySection &&
          ref.read(unifiedLibraryResultsForProvider(text)).isNotEmpty) {
        return true;
      }
      if (matchingGoToTargets(ref, text, context.l10n).isNotEmpty) {
        return true;
      }
      return false;
    }

    void closeResults() {
      if (portal.isShowing) portal.hide();
    }

    void closeAndClearHost() {
      closeResults();
      onNavigate?.call();
    }

    int caretOf(String value) {
      final caret = controller.selection.baseOffset;
      return caret < 0 ? value.length : caret;
    }

    void handleChanged(String value) {
      onChanged(value);
      if (focusNode.hasFocus && canShow(value, caretOf(value))) {
        if (!portal.isShowing) portal.show();
      } else {
        closeResults();
      }
    }

    // A host-side clear (a History section row navigates without going through
    // close) hides the dropdown. Deferred past the frame: this effect can run
    // inside the build/layout phase the clear itself triggered, where the
    // portal refuses show/hide.
    useEffect(() {
      if (query.trim().isEmpty && portal.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) closeResults();
        });
      }
      return null;
    }, [query]);

    // Ctrl+F registration. Provider writes are banned during the build phase
    // (effect setup runs inside it), so every write goes through a post-frame
    // callback guarded by mount state. The field stays registered while
    // mounted — a blur (clicking elsewhere) must not unregister it, or Ctrl+F
    // falls back to the overlay. Only disposal clears it; the global host
    // ignores nodes on inactive branches/routes.
    useEffect(() {
      // Captured, not read lazily: ref is unusable once the widget is
      // unmounted, but the controller itself is a plain state object.
      final registration = ref.read(desktopSearchFocusNodeProvider.notifier);
      void register() {
        if (context.mounted) registration.state = focusNode;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => register());
      void onFocus() {
        if (!context.mounted || !focusNode.hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          register();
          if (canShow(controller.text, caretOf(controller.text)) &&
              !portal.isShowing) {
            portal.show();
          }
        });
      }

      focusNode.addListener(onFocus);
      return () {
        focusNode.removeListener(onFocus);
        // Deferred past the frame: unmount can run inside the build phase
        // (a pop rebuilds the tree), where provider writes are banned.
        if (registration.state == focusNode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (registration.state == focusNode) registration.state = null;
          });
        }
      };
    }, [focusNode]);

    void setText(String text, [int? caret]) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
      );
      handleChanged(text);
      focusNode.requestFocus();
    }

    final caretRaw = controller.selection.baseOffset;
    final caret = caretRaw < 0 ? controller.text.length : caretRaw;
    final token = activeTokenAt(controller.text, caret);

    final scheme = Theme.of(context).colorScheme;
    const iconConstraints = BoxConstraints(minWidth: 36, minHeight: 36);
    return MouseRegion(
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: Container(
        height: 40,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hovered.value
                ? scheme.onSurface.withValues(alpha: 0.18)
                : scheme.outlineVariant,
          ),
        ),
        child: OverlayPortal(
          controller: portal,
          overlayChildBuilder: (context) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: closeResults,
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 8),
                child: SizedBox(
                  width: fieldWidth.value ?? 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                    ),
                    child: Material(
                      color: scheme.surfaceContainer,
                      elevation: 8,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: UnifiedSearchResults(
                        query: controller.text,
                        close: closeAndClearHost,
                        caret: caret,
                        showLibrarySection: showLibrarySection,
                        leading: leading,
                        onSetQuery: setText,
                        onApplySuggestion: (s) {
                          final edit = applySuggestion(
                            controller.text,
                            token,
                            s,
                          );
                          setText(edit.text, edit.caret);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape):
                  _CloseSearchDropdownIntent(),
            },
            child: Actions(
              actions: {
                _CloseSearchDropdownIntent: _CloseSearchDropdownAction(
                  // Closed and empty: disabled, so Esc keeps propagating to
                  // the global Esc=Back handler instead of being swallowed.
                  isActive: () =>
                      portal.isShowing || controller.text.isNotEmpty,
                  onInvoke: () {
                    if (portal.isShowing) {
                      closeResults();
                    } else {
                      controller.clear();
                      onChanged('');
                    }
                  },
                ),
              },
              child: CompositedTransformTarget(
                link: link,
                child: TextField(
                  key: targetKey,
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onChanged: handleChanged,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: hintText ?? l.unifiedSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    prefixIconConstraints: iconConstraints,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...suffixActions,
                        if (controller.text.isNotEmpty)
                          IconButton(
                            iconSize: 20,
                            padding: const EdgeInsets.all(8),
                            constraints: iconConstraints,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                              closeResults();
                              focusNode.requestFocus();
                            },
                          ),
                      ],
                    ),
                    suffixIconConstraints: const BoxConstraints(minHeight: 36),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  // Enter opens the top result — a leading section first
                  // (History), then the unified top result like the overlay.
                  onSubmitted: (_) {
                    if (onSubmitLeading?.call() == true) {
                      closeAndClearHost();
                      return;
                    }
                    submitUnifiedQuery(
                      context,
                      ref,
                      controller.text,
                      includeLibrary: showLibrarySection,
                      close: closeAndClearHost,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
