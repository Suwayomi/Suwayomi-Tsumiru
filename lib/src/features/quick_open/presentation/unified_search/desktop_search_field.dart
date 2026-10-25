// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/search_field.dart';
import 'search_tips.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_facets.dart';
import 'unified_search_providers.dart';
import 'unified_search_results.dart';

/// Mounted desktop field for Ctrl+F/Ctrl+P; null falls back to the quick-open overlay.
final desktopSearchFocusNodeProvider = StateProvider<FocusNode?>(
  (Ref ref) => null,
);

class _CloseSearchDropdownIntent extends Intent {
  const _CloseSearchDropdownIntent();
}

class _MoveSearchHighlightIntent extends Intent {
  const _MoveSearchHighlightIntent(this.delta);

  /// +1 for Down, -1 for Up.
  final int delta;
}

class _MoveSearchHighlightAction extends Action<_MoveSearchHighlightIntent> {
  _MoveSearchHighlightAction({
    required this.isActive,
    required this.onInvoke,
  });

  final bool Function() isActive;
  final void Function(int delta) onInvoke;

  @override
  bool get isActionEnabled => isActive();

  @override
  Object? invoke(_MoveSearchHighlightIntent intent) {
    onInvoke(intent.delta);
    return null;
  }
}

// Disable when idle so Esc propagates to the global Back handler.
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

/// Desktop search dropdown; Esc closes results, then clears text on the next press.
class DesktopSearchField extends HookConsumerWidget {
  const DesktopSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.onNavigate,
    this.leadingBuilder,
    this.hasLeadingResults = false,
    this.showLibrarySection = true,
    this.hintText,
    this.suffixActions = const <Widget>[],
    this.autofocus = false,
    this.onSubmitLeading,
  });

  final String query;

  final ValueChanged<String> onChanged;

  /// Invoked after dropdown navigation so the host can clear its query.
  final VoidCallback? onNavigate;

  /// Leading sections must use SelectableRowBuilder to join keyboard order before unified rows.
  final List<Widget> Function(SelectableRowBuilder selectable)? leadingBuilder;

  final bool hasLeadingResults;

  final bool showLibrarySection;

  /// Null uses the unified hint.
  final String? hintText;

  final List<Widget> suffixActions;

  final bool autofocus;

  /// True means a leading result navigated; null or false falls back to the unified top result.
  final bool Function()? onSubmitLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final controller = useMemoized(() => DslSearchController(text: query));
    useEffect(() => controller.dispose, [controller]);
    // Update the controller after the frame; notifying during build can reach layout.
    useEffect(() {
      if (controller.text != query) controller.text = query;
      return null;
    }, [query]);
    useListenable(controller); // rebuild on text OR caret move

    final focusNode = useFocusNode();
    final selection = useMemoized(UnifiedSearchSelection.new);
    useEffect(() => selection.dispose, [selection]);
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
      // Operator autocomplete alone can make a dropdown useful, e.g. unread:.
      final caretOffset = (caret ?? text.length).clamp(0, text.length);
      if (suggestFor(
        activeTokenAt(text, caretOffset),
        ref.read(unifiedLibraryFacetsProvider),
      ).isNotEmpty) {
        return true;
      }
      if (plainQueryText(text).isNotEmpty) return true;
      if (showLibrarySection &&
          ref.read(unifiedLibraryResultsForProvider(text)).isNotEmpty) {
        return true;
      }
      if (matchingGoToTargets(ref, text, context.l10n).isNotEmpty) {
        return true;
      }
      if (matchingSettingsEntries(ref, context, text).isNotEmpty) {
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
      selection.reset();
      if (focusNode.hasFocus && canShow(value, caretOf(value))) {
        if (!portal.isShowing) portal.show();
      } else {
        closeResults();
      }
    }

    // Defer portal changes past build/layout, including host-side clears.
    useEffect(() {
      if (query.trim().isEmpty && portal.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) closeResults();
        });
      }
      return null;
    }, [query]);

    // Register post-frame until disposal; unregistering on blur would send Ctrl+F to the overlay.
    useEffect(() {
      // Capture the notifier now; ref is unusable after unmount.
      final registration = ref.read(desktopSearchFocusNodeProvider.notifier);
      void register() {
        if (context.mounted && registration.mounted) {
          registration.state = focusNode;
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => register());
      void onFocus() {
        if (!context.mounted || !focusNode.hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          register();
          if (canShow(controller.text, caretOf(controller.text)) &&
              !portal.isShowing) {
            selection.reset();
            portal.show();
          }
        });
      }

      focusNode.addListener(onFocus);
      return () {
        focusNode.removeListener(onFocus);
        // Unmount may run during build, so defer provider writes.
        if (registration.mounted && registration.state == focusNode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (registration.mounted && registration.state == focusNode) {
              registration.state = null;
            }
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
                        selection: selection,
                        leadingBuilder: leadingBuilder,
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
              SingleActivator(LogicalKeyboardKey.arrowDown):
                  _MoveSearchHighlightIntent(1),
              SingleActivator(LogicalKeyboardKey.arrowUp):
                  _MoveSearchHighlightIntent(-1),
            },
            child: Actions(
              actions: {
                _CloseSearchDropdownIntent: _CloseSearchDropdownAction(
                  // Let Esc reach global Back when there is no dropdown or query.
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
                _MoveSearchHighlightIntent: _MoveSearchHighlightAction(
                  // Preserve field Up/Down behavior while the dropdown is closed.
                  isActive: () => portal.isShowing,
                  onInvoke: (delta) {
                    if (delta > 0) {
                      selection.moveDown();
                    } else {
                      selection.moveUp();
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
                    prefixIcon: const Icon(FluentIcons.search_24_regular, size: 20),
                    prefixIconConstraints: iconConstraints,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Library operators also filter library hits in app-wide search.
                        IconButton(
                          iconSize: 20,
                          padding: const EdgeInsets.all(8),
                          constraints: iconConstraints,
                          icon: const Icon(
                            FluentIcons.question_circle_24_regular,
                          ),
                          tooltip: l.searchTips,
                          onPressed: () => showSearchTips(context),
                        ),
                        ...suffixActions,
                        if (controller.text.isNotEmpty)
                          IconButton(
                            iconSize: 20,
                            padding: const EdgeInsets.all(8),
                            constraints: iconConstraints,
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                              selection.reset();
                              closeResults();
                              focusNode.requestFocus();
                            },
                          ),
                      ],
                    ),
                    suffixIconConstraints: const BoxConstraints(minHeight: 36),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onSubmitted: (_) {
                    if (selection.activateSelected()) return;
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
