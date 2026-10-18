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

    bool canShow(String text) {
      if (text.trim().isEmpty || fieldWidth.value == null) return false;
      if (hasLeadingResults) return true;
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

    void handleChanged(String value) {
      onChanged(value);
      if (focusNode.hasFocus && canShow(value)) {
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
    // callback guarded by mount state; routes without a field simply leave a
    // null (or detached) node behind and the overlay path stays.
    useEffect(() {
      void register() {
        if (context.mounted) {
          ref.read(desktopSearchFocusNodeProvider.notifier).state = focusNode;
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => register());
      void onFocus() {
        if (!context.mounted) return;
        if (!focusNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            if (ref.read(desktopSearchFocusNodeProvider) == focusNode) {
              ref.read(desktopSearchFocusNodeProvider.notifier).state = null;
            }
          });
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          register();
          if (canShow(controller.text) && !portal.isShowing) portal.show();
        });
      }

      focusNode.addListener(onFocus);
      return () => focusNode.removeListener(onFocus);
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
                _CloseSearchDropdownIntent:
                    CallbackAction<_CloseSearchDropdownIntent>(
                      onInvoke: (_) {
                        if (portal.isShowing) {
                          closeResults();
                        } else if (controller.text.isNotEmpty) {
                          controller.clear();
                          onChanged('');
                        } else {
                          return null; // let Esc bubble (back navigation)
                        }
                        return null;
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
                    suffixIconConstraints: const BoxConstraints(minHeight: 40),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  // Enter opens the top result — shared with the overlay.
                  onSubmitted: (_) => submitUnifiedQuery(
                    context,
                    ref,
                    controller.text,
                    includeLibrary: showLibrarySection,
                    close: closeAndClearHost,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
