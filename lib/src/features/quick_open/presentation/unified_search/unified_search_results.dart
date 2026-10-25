// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../routes/navigation.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/server_image.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../settings/search/settings_search_registry.dart';
import 'go_to_targets.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_facets.dart';
import 'unified_search_providers.dart';

const List<String> _searchExamples = [
  'unread:true',
  'downloaded:true',
  'status:ongoing',
];

List<GoToTarget> _categoryTargets(WidgetRef ref) => [
  for (final c in ref.watch(visibleCategoryListProvider).value ?? const [])
    GoToTarget(
      label: (_) => c.name,
      icon: FluentIcons.folder_24_regular,
      // push rebuilds LibraryScreen for the chosen category; go reuses its current tab controller.
      navigate: (ctx) => LibraryRoute(categoryId: c.id).push(ctx),
    ),
];

/// Empty queries return all launcher destinations.
List<GoToTarget> matchingGoToTargets(
  WidgetRef ref,
  String query,
  AppLocalizations l,
) {
  final extra = _categoryTargets(ref);
  final includeAccount = ref.watch(showAccountEntryProvider);
  if (query.trim().isEmpty) {
    return [
      ...appGoToTargets(
        includeHotkeys: isKeyboardRuntime,
        includeAccount: includeAccount,
      ),
      ...extra,
    ];
  }
  return matchGoToTargets(
    query,
    l,
    includeHotkeys: isKeyboardRuntime,
    includeAccount: includeAccount,
    extra: extra,
  );
}

List<SettingsSearchEntry> matchingSettingsEntries(
  WidgetRef ref,
  BuildContext context,
  String query,
) => matchSettingsEntries(
  entries: allSettingsSearchEntries,
  l: context.l10n,
  query: query,
  isVisible: (e) => e.visible(ref, context),
);

/// Opens the top Library, Go-to, or Settings result, then global search; true means navigation occurred.
bool submitUnifiedQuery(
  BuildContext context,
  WidgetRef ref,
  String query, {
  required bool includeLibrary,
  required VoidCallback close,
}) {
  if (query.trim().isEmpty) return false;
  if (includeLibrary) {
    final hits = ref.read(unifiedLibraryResultsForProvider(query));
    if (hits.isNotEmpty) {
      MangaRoute(mangaId: hits.first.id).push(context);
      close();
      return true;
    }
  }
  final goTo = matchingGoToTargets(ref, query, context.l10n);
  if (goTo.isNotEmpty) {
    goTo.first.navigate(context);
    close();
    return true;
  }
  final settings = matchingSettingsEntries(ref, context, query);
  if (settings.isNotEmpty) {
    settings.first.open(context);
    close();
    return true;
  }
  final plain = plainQueryText(query);
  if (plain.isNotEmpty) {
    openGlobalSearch(context, query: plain);
    close();
    return true;
  }
  return false; // pure operator query, nothing typed to hand off
}

/// Leading sections use this builder to join keyboard selection before unified result rows.
typedef SelectableRowBuilder =
    Widget Function({
      required VoidCallback action,
      required Widget Function(VoidCallback onTap) tile,
    });

/// Host-owned selection keeps field focus; null selects nothing, Down stops at the end, Up can clear.
class UnifiedSearchSelection extends ChangeNotifier {
  int? _index;
  List<VoidCallback> _rows = const [];

  int? get index => _index;

  int get length => _rows.length;

  void _setIndex(int? value) {
    if (_index == value) return;
    _index = value;
    notifyListeners();
  }

  /// Called post-frame in visual order; only a count change affecting selection notifies listeners.
  void setRows(List<VoidCallback> rows) {
    _rows = rows;
    if (_index != null && _index! >= rows.length) {
      _index = rows.isEmpty ? null : rows.length - 1;
      notifyListeners();
    }
  }

  void moveDown() {
    if (_rows.isEmpty) return;
    _setIndex(_index == null ? 0 : (_index! + 1).clamp(0, _rows.length - 1));
  }

  void moveUp() {
    if (_index == null) return;
    _setIndex(_index! == 0 ? null : _index! - 1);
  }

  void hover(int index) {
    if (index < 0 || index >= _rows.length) return;
    _setIndex(index);
  }

  void reset() => _setIndex(null);

  /// False means no selection, allowing the host to use its top-result fallback.
  bool activateSelected() {
    final i = _index;
    if (i == null || i < 0 || i >= _rows.length) return false;
    _rows[i]();
    return true;
  }
}

class UnifiedSearchResults extends HookConsumerWidget {
  const UnifiedSearchResults({
    super.key,
    required this.query,
    required this.close,
    this.caret,
    this.showLibrarySection = true,
    this.leadingBuilder,
    required this.onSetQuery,
    required this.onApplySuggestion,
    required this.selection,
  });

  final String query;

  /// Called after navigation so the host can close results.
  final VoidCallback close;

  /// Null puts autocomplete at the end of the query.
  final int? caret;

  final bool showLibrarySection;

  /// Leading rows use SelectableRowBuilder to precede unified rows in keyboard order.
  final List<Widget> Function(SelectableRowBuilder selectable)? leadingBuilder;

  final ValueChanged<String> onSetQuery;

  final ValueChanged<SearchSuggestion> onApplySuggestion;

  /// Host-owned selection; keyboard navigation leaves focus in the text field.
  final UnifiedSearchSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useListenable(selection);
    final l = context.l10n;
    // Pin server-backed dependencies while open so typing does not refetch them.
    pinSettingsSearchProviders(ref);
    final caret = this.caret ?? query.length;
    final token = activeTokenAt(query, caret);
    final suggestions = suggestFor(
      token,
      ref.watch(unifiedLibraryFacetsProvider),
    );
    final hasQuery = query.trim().isNotEmpty;
    final libraryHits = showLibrarySection
        ? ref.watch(unifiedLibraryResultsForProvider(query))
        : const <MangaDto>[];
    final goToHits = matchingGoToTargets(ref, query, l);
    final settingsHits = hasQuery
        ? matchSettingsEntries(
            entries: allSettingsSearchEntries,
            l: l,
            query: query,
            isVisible: (e) => e.visible(ref, context),
          )
        : const <SettingsSearchEntry>[];
    final plainQuery = plainQueryText(query);

    final activations = <VoidCallback>[];
    final rowContexts = <int, BuildContext>{};
    var nextRow = 0;

    Widget selectable({
      required VoidCallback action,
      required Widget Function(VoidCallback onTap) tile,
    }) {
      final index = nextRow++;
      activations.add(action);
      final highlighted = selection.index == index;
      return Builder(
        builder: (context) {
          rowContexts[index] = context;
          return MouseRegion(
            onEnter: (_) => selection.hover(index),
            child: Semantics(
              selected: highlighted,
              child: Material(
                color: highlighted
                    ? Theme.of(context).hoverColor
                    : Colors.transparent,
                child: tile(action),
              ),
            ),
          );
        },
      );
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => selection.setRows(activations),
      );
      return null;
    });

    final highlighted = selection.index;
    useEffect(() {
      if (highlighted == null) return null;
      // Wait for row contexts after layout; text edits may have reset selection meanwhile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (selection.index != highlighted) return;
        final rowContext = rowContexts[highlighted];
        if (rowContext == null || !rowContext.mounted) return;
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      });
      return null;
    }, [highlighted]);

    // Build every row eagerly so keyboard selection can scroll any index into view.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasQuery) ...[
            SearchSectionHeader(l.unifiedSearchExamplesSection),
            for (final ex in _searchExamples)
              selectable(
                action: () => onSetQuery(ex),
                tile: (onTap) => ListTile(
                  dense: true,
                  leading: const Icon(FluentIcons.flash_24_regular),
                  title: Text(ex),
                  onTap: onTap,
                ),
              ),
          ],
          ...?leadingBuilder?.call(selectable),
          if (suggestions.isNotEmpty) ...[
            SearchSectionHeader(l.unifiedSearchFiltersSection),
            for (final s in suggestions)
              selectable(
                action: () => onApplySuggestion(s),
                tile: (onTap) => ListTile(
                  dense: true,
                  leading: Icon(
                    s.isKey ? FluentIcons.braces_24_regular : FluentIcons.options_24_regular,
                  ),
                  title: Text(s.display),
                  onTap: onTap,
                ),
              ),
          ],
          if (hasQuery && libraryHits.isNotEmpty) ...[
            SearchSectionHeader(l.unifiedSearchLibrarySection),
            for (final m in libraryHits)
              selectable(
                action: () {
                  MangaRoute(mangaId: m.id).push(context);
                  close();
                },
                tile: (onTap) => ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ServerImage(
                      imageUrl: m.displayCoverUrl,
                      fallbackImageUrl: m.thumbnailUrl,
                      coverVersion: m.coverVersion,
                      size: const Size(40, 56),
                    ),
                  ),
                  title: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: _mangaSubtitle(context, m),
                  onTap: onTap,
                ),
              ),
          ],
          if (goToHits.isNotEmpty) ...[
            SearchSectionHeader(l.unifiedSearchGoToSection),
            for (final t in goToHits)
              selectable(
                action: () {
                  t.navigate(context);
                  close();
                },
                tile: (onTap) => ListTile(
                  leading: Icon(t.icon),
                  title: Text(t.label(l)),
                  subtitle: t.subtitle == null
                      ? null
                      : Text(
                          t.subtitle!(l),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  onTap: onTap,
                ),
              ),
          ],
          if (settingsHits.isNotEmpty) ...[
            SearchSectionHeader(l.settings),
            for (final e in settingsHits)
              selectable(
                action: () {
                  e.open(context);
                  close();
                },
                tile: (onTap) => SettingsSearchResultRow(
                  entry: e,
                  query: query,
                  onTap: onTap,
                ),
              ),
          ],
          if (plainQuery.isNotEmpty) ...[
            const Divider(height: 1),
            selectable(
              action: () {
                openGlobalSearch(context, query: plainQuery);
                close();
              },
              tile: (onTap) => ListTile(
                leading: const Icon(FluentIcons.globe_search_24_regular),
                title: Text(l.unifiedSearchAllSources(plainQuery)),
                onTap: onTap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _mangaSubtitle(BuildContext context, MangaDto manga) {
    final source = manga.source?.displayName;
    final parts = [
      if (source != null && source.isNotEmpty) source,
      if (manga.user.unreadCount > 0) '${manga.user.unreadCount} unread',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodySmall,
    );
  }
}

class SearchSectionHeader extends StatelessWidget {
  const SearchSectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colorScheme.primary,
        ),
      ),
    ),
  );
}
