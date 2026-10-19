// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../routes/navigation.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/server_image.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../settings/search/settings_search_registry.dart';
import 'go_to_targets.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_facets.dart';
import 'unified_search_providers.dart';

// A few operators worth teaching in the empty state — each filters immediately
// and shows a different metatag, so the autocomplete can carry the rest.
const List<String> _searchExamples = [
  'unread:true',
  'downloaded:true',
  'status:ongoing',
];

/// "Go to" category targets, shared by the list and the Enter handler so both
/// offer the same destinations.
List<GoToTarget> _categoryTargets(WidgetRef ref) => [
  for (final c in ref.watch(visibleCategoryListProvider).value ?? const [])
    GoToTarget(
      label: (_) => c.name,
      icon: Icons.folder_rounded,
      // .push (not .go) rebuilds LibraryScreen so its DefaultTabController
      // lands on the chosen category — .go reuses the live screen and the
      // tab never changes.
      navigate: (ctx) => LibraryRoute(categoryId: c.id).push(ctx),
    ),
];

/// Go-to destinations matching [query] (empty query = the full launcher list).
List<GoToTarget> matchingGoToTargets(
  WidgetRef ref,
  String query,
  AppLocalizations l,
) {
  final extra = _categoryTargets(ref);
  if (query.trim().isEmpty) {
    return [...appGoToTargets(includeHotkeys: isKeyboardRuntime), ...extra];
  }
  return matchGoToTargets(
    query,
    l,
    includeHotkeys: isKeyboardRuntime,
    extra: extra,
  );
}

/// Settings entries matching [query], visibility-filtered for this ref+context.
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

/// Enter opens the top result (library first, then go-to, then settings),
/// falling back to the global handoff — not always global. Returns true when
/// it navigated, so callers can clear their field; every entry point
/// (overlay, desktop dropdowns) shares this so Enter behaves one way
/// everywhere.
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

/// The unified results list: Examples (empty query), Filters, Library hits ≤6
/// with source • unread subtitle, Go to, Search all sources. Query in, results
/// out — every host (the phone/tablet overlay, the desktop dropdowns) renders
/// this so the sections stay identical.
class UnifiedSearchResults extends ConsumerWidget {
  const UnifiedSearchResults({
    super.key,
    required this.query,
    required this.close,
    this.caret,
    this.showLibrarySection = true,
    this.leading = const <Widget>[],
    required this.onSetQuery,
    required this.onApplySuggestion,
  });

  /// The text being searched.
  final String query;

  /// Called after any navigation, so the host can hide/clear.
  final VoidCallback close;

  /// Caret offset for operator autocomplete; null puts it at the end.
  final int? caret;

  /// False hides the Library section (the Library grid is already filtered).
  final bool showLibrarySection;

  /// Extra sections rendered before the unified ones (History on its page).
  final List<Widget> leading;

  /// Tapping an example replaces the field text (host splices its controller).
  final ValueChanged<String> onSetQuery;

  /// Tapping a filter suggestion splices it into the field text.
  final ValueChanged<SearchSuggestion> onApplySuggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    // Keep the server-backed search dependencies alive for the whole open
    // search, so typing never refetches them (see pinSettingsSearchProviders).
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

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        if (!hasQuery) ...[
          SearchSectionHeader(l.unifiedSearchExamplesSection),
          for (final ex in _searchExamples)
            ListTile(
              dense: true,
              leading: const Icon(Icons.bolt_rounded),
              title: Text(ex),
              onTap: () => onSetQuery(ex),
            ),
        ],
        ...leading,
        if (suggestions.isNotEmpty) ...[
          SearchSectionHeader(l.unifiedSearchFiltersSection),
          for (final s in suggestions)
            ListTile(
              dense: true,
              leading: Icon(
                s.isKey ? Icons.data_object_rounded : Icons.tune_rounded,
              ),
              title: Text(s.display),
              onTap: () => onApplySuggestion(s),
            ),
        ],
        if (hasQuery && libraryHits.isNotEmpty) ...[
          SearchSectionHeader(l.unifiedSearchLibrarySection),
          for (final m in libraryHits)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ServerImage(
                  imageUrl: m.thumbnailUrl ?? "",
                  size: const Size(40, 56),
                ),
              ),
              title: Text(
                m.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _mangaSubtitle(context, m),
              onTap: () {
                MangaRoute(mangaId: m.id).push(context);
                close();
              },
            ),
        ],
        if (goToHits.isNotEmpty) ...[
          SearchSectionHeader(l.unifiedSearchGoToSection),
          for (final t in goToHits)
            ListTile(
              leading: Icon(t.icon),
              title: Text(t.label(l)),
              onTap: () {
                t.navigate(context);
                close();
              },
            ),
        ],
        if (settingsHits.isNotEmpty) ...[
          SearchSectionHeader(l.settings),
          for (final e in settingsHits)
            SettingsSearchResultRow(
              entry: e,
              query: query,
              onTap: () {
                e.open(context);
                close();
              },
            ),
        ],
        if (plainQuery.isNotEmpty) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.travel_explore_rounded),
            title: Text(l.unifiedSearchAllSources(plainQuery)),
            onTap: () {
              openGlobalSearch(context, query: plainQuery);
              close();
            },
          ),
        ],
      ],
    );
  }

  // Source name + unread count, whichever are present; null when neither.
  Widget? _mangaSubtitle(BuildContext context, MangaDto manga) {
    final source = manga.source?.displayName;
    final parts = [
      if (source != null && source.isNotEmpty) source,
      if (manga.unreadCount > 0) '${manga.unreadCount} unread',
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
