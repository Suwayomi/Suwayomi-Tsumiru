// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../routes/navigation.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/cover_row_section.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../history/domain/history_group.dart';
import '../../../history/domain/history_item.dart';
import '../../../history/presentation/history_controller.dart';
import '../../../library/domain/library_search_query.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import 'unified_search_autocomplete.dart';
import 'unified_search_facets.dart';
import 'unified_search_providers.dart';
import 'unified_search_results.dart';

// Operator examples worth teaching while the field is empty. Same set as the
// unified results so both hosts teach the same filters.
const List<String> _phoneSearchExamples = [
  'unread:true',
  'downloaded:true',
  'status:ongoing',
];

/// Which page opened the phone search. Library, History and the Sources tab
/// have their own filter, so they get the page row first; every other page
/// searches the app without one.
enum PhoneSearchOrigin { library, history, sources, plain }

/// The page's live filter text, if it has one and it is non-blank.
String? _activeFilter(WidgetRef ref, PhoneSearchOrigin origin) {
  final text = switch (origin) {
    PhoneSearchOrigin.library => ref.watch(libraryQueryProvider),
    PhoneSearchOrigin.history => ref.watch(historySearchQueryProvider),
    PhoneSearchOrigin.sources => ref.watch(sourceSearchQueryProvider),
    PhoneSearchOrigin.plain => null,
  };
  return text.isNotBlank ? text : null;
}

void _clearFilter(WidgetRef ref, PhoneSearchOrigin origin) {
  switch (origin) {
    case PhoneSearchOrigin.library:
      ref.read(libraryQueryProvider.notifier).update('');
    case PhoneSearchOrigin.history:
      ref.read(historySearchQueryProvider.notifier).clearQuery();
    case PhoneSearchOrigin.sources:
      ref.read(sourceSearchQueryProvider.notifier).update(null);
    case PhoneSearchOrigin.plain:
      break;
  }
}

void _applyFilter(WidgetRef ref, PhoneSearchOrigin origin, String query) {
  switch (origin) {
    case PhoneSearchOrigin.library:
      ref.read(libraryQueryProvider.notifier).update(query);
    case PhoneSearchOrigin.history:
      ref.read(historySearchQueryProvider.notifier).updateQuery(query);
    case PhoneSearchOrigin.sources:
      ref.read(sourceSearchQueryProvider.notifier).update(query);
    case PhoneSearchOrigin.plain:
      break;
  }
}

/// The tappable search entry for phone pages: a search icon for the app bar
/// ([box] false) or a full-width box for under the title ([box] true, used
/// when the "Persistent search bar" setting is on). Either opens the
/// full-screen search overlay; typing there never touches the page until the
/// page row is applied.
class PhoneSearchEntry extends HookConsumerWidget {
  const PhoneSearchEntry({super.key, required this.origin, this.box = false});

  final PhoneSearchOrigin origin;
  final bool box;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = useMemoized(OverlayPortalController.new);
    void open() {
      if (!portal.isShowing) portal.show();
    }

    void close() {
      if (portal.isShowing) portal.hide();
    }

    // Watched in both styles so an applied filter survives while the entry
    // is mounted (the filter providers are auto-disposed when unwatched).
    final activeFilter = _activeFilter(ref, origin);

    return OverlayPortal(
      controller: portal,
      overlayChildBuilder: (_) =>
          PhoneSearchOverlay(origin: origin, onClose: close),
      child: box
          ? _PhoneSearchBox(origin: origin, onOpen: open)
          : IconButton(
              tooltip: context.l10n.search,
              // Tinted while filtered, so a short list reads as "filtered"
              // rather than empty — same idiom as the filter icons.
              color: activeFilter != null ? context.colorScheme.primary : null,
              icon: const Icon(Icons.search_rounded),
              onPressed: open,
            ),
    );
  }
}

/// The tappable box shown under the title when the "Persistent search bar"
/// setting is on. Shows the page's active filter when there is one (with a
/// clear button); tapping anywhere else opens the search overlay.
class _PhoneSearchBox extends ConsumerWidget {
  const _PhoneSearchBox({required this.origin, required this.onOpen});

  final PhoneSearchOrigin origin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colorScheme;
    final active = _activeFilter(ref, origin);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  active ?? context.l10n.unifiedSearchHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: active == null
                      ? context.textTheme.bodyMedium?.copyWith(
                          color: context.theme.hintColor,
                        )
                      : context.textTheme.bodyMedium,
                ),
              ),
              if (active != null)
                IconButton(
                  tooltip: context.l10n.reset,
                  iconSize: 20,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _clearFilter(ref, origin),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom slot for the tappable search box, optionally above an existing tab
/// bar. Only used on phone pages when the "Persistent search bar" setting is
/// on; pages keep their own `bottom` otherwise.
class PhoneSearchBoxBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const PhoneSearchBoxBottom({super.key, required this.origin, this.below});

  final PhoneSearchOrigin origin;
  final PreferredSizeWidget? below;

  static const double boxHeight = 56;

  @override
  Size get preferredSize =>
      Size.fromHeight(boxHeight + (below?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      PhoneSearchEntry(origin: origin, box: true),
      ?below,
    ],
  );
}

/// Clears the page's filter on phone pages using the search icon (the box
/// carries its own clear button). Renders nothing when the persistent box is
/// on or no filter is active, so icon-mode pages keep a way to unfilter.
class PhoneSearchClearFilter extends ConsumerWidget {
  const PhoneSearchClearFilter({super.key, required this.origin});

  final PhoneSearchOrigin origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(libraryPersistentSearchBarProvider).ifNull()) {
      return const SizedBox.shrink();
    }
    if (_activeFilter(ref, origin) == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: context.l10n.reset,
      icon: const Icon(Icons.close_rounded),
      onPressed: () => _clearFilter(ref, origin),
    );
  }
}

/// The full-screen phone search: back arrow, autofocus field, clear button on
/// top; results below on a solid surface background. The query lives in this
/// widget's own controller, so typing never changes the page underneath —
/// only the page row writes the page's filter provider.
class PhoneSearchOverlay extends HookConsumerWidget {
  const PhoneSearchOverlay({
    super.key,
    required this.origin,
    required this.onClose,
  });

  final PhoneSearchOrigin origin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final cs = context.colorScheme;
    final controller = useMemoized(DslSearchController.new);
    useEffect(() => controller.dispose, [controller]);
    useListenable(controller);
    final focusNode = useFocusNode();
    final query = controller.text;

    void applyPage() {
      final q = controller.text;
      if (q.trim().isEmpty || origin == PhoneSearchOrigin.plain) return;
      _applyFilter(ref, origin, q);
      onClose();
    }

    // Leaving through a result clears the search text; the page providers
    // were never touched, so the page underneath is unchanged.
    void leave(VoidCallback navigate) {
      controller.clear();
      navigate();
      onClose();
    }

    void closeAndClear() {
      controller.clear();
      onClose();
    }

    void submit() {
      final q = controller.text;
      if (q.trim().isEmpty) return;
      if (origin != PhoneSearchOrigin.plain &&
          _hasPageMatches(ref, origin, q)) {
        applyPage();
        return;
      }
      submitUnifiedQuery(
        context,
        ref,
        q,
        includeLibrary: true,
        close: closeAndClear,
      );
    }

    void setQuery(String text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      focusNode.requestFocus();
    }

    void applySuggestionAndStay(SearchSuggestion s) {
      final caretRaw = controller.selection.baseOffset;
      final caret = caretRaw < 0 ? controller.text.length : caretRaw;
      final edit = applySuggestion(
        controller.text,
        activeTokenAt(controller.text, caret),
        s,
      );
      controller.value = TextEditingValue(
        text: edit.text,
        selection: TextSelection.collapsed(offset: edit.caret),
      );
      focusNode.requestFocus();
    }

    final caretRaw = controller.selection.baseOffset;
    final caret = caretRaw < 0 ? query.length : caretRaw;

    // System back closes the overlay first, like a dialog.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: cs.surface,
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: l.back,
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: onClose,
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            style: context.textTheme.bodyLarge,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: l.unifiedSearchHint,
                            ),
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                        if (query.isNotEmpty)
                          IconButton(
                            tooltip: l.close,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: controller.clear,
                          ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _PhoneSearchResults(
                        query: query,
                        caret: caret,
                        origin: origin,
                        onApplyPage: applyPage,
                        onLeave: leave,
                        onSetQuery: setQuery,
                        onApplySuggestion: applySuggestionAndStay,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<HistoryItemDto> _historyMatches(List<HistoryGroup> groups, String query) =>
    [for (final g in groups) ...g.filterByQuery(query).items];

/// Whether applying [q] to the Library page would show at least one series,
/// using the same matcher the library filter uses ([MangaDto.query]) so plain
/// words match author/genre/tags too. Pure-operator queries (e.g.
/// `unread:true`), service-scoped `tracked:` (needs the trackers map the
/// overlay doesn't load), and queries parsing to nothing (half-typed `tag:`)
/// can't be judged cheaply here — applying them is always valid, so the row
/// stays enabled.
bool _libraryPageHasMatches(List<MangaDto> library, String q) {
  final query = q.trim();
  if (query.isEmpty) return false;
  if (LibrarySearchQuery.parse(query).isEmpty) return true;
  if (LibrarySearchQuery.plainText(query).trim().isEmpty) return true;
  if (_namesTrackerService(query)) return true;
  return library.any((m) => m.query(query));
}

/// Whether [q] holds a `tracked:<service>` term, which only resolves with the
/// trackers map (a bare `tracked:true`/`false` is self-contained).
bool _namesTrackerService(String q) {
  for (final m in RegExp(
    r'(?:^|[\s,{])-?tracked:([^|\s,}]+)',
    caseSensitive: false,
  ).allMatches(q)) {
    switch (m.group(1)!.toLowerCase()) {
      case 'true' || 'yes' || '1' || 'false' || 'no' || '0':
        break;
      default:
        return true;
    }
  }
  return false;
}

/// The Sources tab shows pinned sources (name-filtered) above the grouped
/// rest, so the row matches that same combined list ([searchableSources] is
/// pinned first, then the language-filtered rest).
List<SourceDto> _sourcePageMatches(List<SourceDto> searchable, String query) =>
    searchable.where((s) => s.name.query(query)).toList();

bool _hasPageMatches(WidgetRef ref, PhoneSearchOrigin origin, String q) {
  if (q.trim().isEmpty) return false;
  return switch (origin) {
    PhoneSearchOrigin.library => _libraryPageHasMatches(
      ref.read(libraryMangaListProvider).value ?? const [],
      q,
    ),
    PhoneSearchOrigin.history => _historyMatches(
      ref.read(historyGroupedByDateProvider),
      q,
    ).isNotEmpty,
    PhoneSearchOrigin.sources => _sourcePageMatches(
      ref.read(searchableSourcesProvider).value ?? const [],
      q,
    ).isNotEmpty,
    PhoneSearchOrigin.plain => false,
  };
}

String _historySubtitle(HistoryItemDto item) {
  final readAt = item.readAt;
  final time = readAt != null ? DateFormat.Hm().format(readAt) : '';
  return time.isEmpty ? item.name : '${item.name} · $time';
}

/// Results for the phone overlay, top to bottom: the page row (always first
/// while text is non-empty on pages with their own filter), up to 3 matches
/// from the current page, Library (a swipeable cover row on the Library page,
/// list rows everywhere else), Go to, Search all sources.
class _PhoneSearchResults extends ConsumerWidget {
  const _PhoneSearchResults({
    required this.query,
    required this.caret,
    required this.origin,
    required this.onApplyPage,
    required this.onLeave,
    required this.onSetQuery,
    required this.onApplySuggestion,
  });

  final String query;
  final int caret;
  final PhoneSearchOrigin origin;
  final VoidCallback onApplyPage;
  final void Function(VoidCallback navigate) onLeave;
  final ValueChanged<String> onSetQuery;
  final ValueChanged<SearchSuggestion> onApplySuggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final cs = context.colorScheme;
    final hasQuery = query.trim().isNotEmpty;
    final libraryHits = ref.watch(unifiedLibraryResultsForProvider(query));
    final historyMatches = origin == PhoneSearchOrigin.history
        ? _historyMatches(ref.watch(historyGroupedByDateProvider), query)
        : const <HistoryItemDto>[];
    final sourceMatches = origin == PhoneSearchOrigin.sources
        ? _sourcePageMatches(
            ref.watch(searchableSourcesProvider).value ?? const [],
            query,
          )
        : const <SourceDto>[];
    final libraryPageMatches = origin == PhoneSearchOrigin.library
        ? _libraryPageHasMatches(
            ref.watch(libraryMangaListProvider).value ?? const [],
            query,
          )
        : false;
    final goToHits = matchingGoToTargets(ref, query, l);
    final plainQuery = plainQueryText(query);
    final suggestions = hasQuery
        ? suggestFor(
            activeTokenAt(query, caret.clamp(0, query.length)),
            ref.watch(unifiedLibraryFacetsProvider),
          )
        : const <SearchSuggestion>[];

    final (
      String pageRowText,
      bool pageHasMatches,
      IconData pageIcon,
    ) = switch (origin) {
      PhoneSearchOrigin.library => (
        l.phoneSearchLibraryFor(query),
        libraryPageMatches,
        Icons.collections_bookmark_rounded,
      ),
      PhoneSearchOrigin.history => (
        l.phoneSearchHistoryFor(query),
        historyMatches.isNotEmpty,
        Icons.history_rounded,
      ),
      PhoneSearchOrigin.sources => (
        l.phoneSearchSourcesFor(query),
        sourceMatches.isNotEmpty,
        Icons.explore_rounded,
      ),
      PhoneSearchOrigin.plain => ('', false, Icons.search_rounded),
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (!hasQuery) ...[
          SearchSectionHeader(l.unifiedSearchExamplesSection),
          for (final ex in _phoneSearchExamples)
            ListTile(
              dense: true,
              leading: const Icon(Icons.bolt_rounded),
              title: Text(ex),
              onTap: () => onSetQuery(ex),
            ),
        ],
        if (hasQuery && origin != PhoneSearchOrigin.plain)
          ListTile(
            selected: pageHasMatches,
            selectedTileColor: cs.secondaryContainer,
            selectedColor: cs.onSurface,
            iconColor: cs.onSurfaceVariant,
            leading: Icon(pageIcon),
            title: Text(
              pageRowText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: pageHasMatches
                ? null
                : Text(
                    l.phoneSearchNoResults,
                    style: context.textTheme.bodySmall,
                  ),
            enabled: pageHasMatches,
            onTap: pageHasMatches ? onApplyPage : null,
          ),
        if (hasQuery &&
            origin == PhoneSearchOrigin.history &&
            historyMatches.isNotEmpty) ...[
          const Divider(height: 1),
          for (final item in historyMatches.take(3))
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ServerImage(
                  imageUrl: item.manga.thumbnailUrl ?? '',
                  size: const Size(40, 56),
                ),
              ),
              title: Text(
                item.manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _historySubtitle(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall,
              ),
              onTap: () => onLeave(
                () => MangaRoute(mangaId: item.manga.id).push(context),
              ),
            ),
        ],
        if (hasQuery &&
            origin == PhoneSearchOrigin.sources &&
            sourceMatches.isNotEmpty) ...[
          const Divider(height: 1),
          for (final source in sourceMatches.take(3))
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ServerImage(
                  imageUrl: source.iconUrl,
                  size: const Size.square(48),
                ),
              ),
              title: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: (source.language?.displayName).isNotBlank
                  ? Text(
                      source.language?.displayName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              onTap: () => onLeave(() {
                ref.read(sourceLastUsedProvider.notifier).update(source.id);
                SourceTypeRoute(
                  sourceId: source.id,
                  sourceType: SourceType.POPULAR,
                ).go(context);
              }),
            ),
        ],
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
          if (origin == PhoneSearchOrigin.library)
            CoverRowSection(
              title: '${l.unifiedSearchLibrarySection} (${libraryHits.length})',
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 110 * 1.5 + 46,
              itemCount: libraryHits.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final m = libraryHits[index];
                return _PhoneLibraryCoverCard(
                  title: m.title,
                  thumbnailUrl: m.thumbnailUrl,
                  onTap: () =>
                      onLeave(() => MangaRoute(mangaId: m.id).push(context)),
                );
              },
            )
          else ...[
            SearchSectionHeader(l.unifiedSearchLibrarySection),
            for (final m in libraryHits)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ServerImage(
                    imageUrl: m.thumbnailUrl ?? '',
                    size: const Size(40, 56),
                  ),
                ),
                title: Text(
                  m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${m.unreadCount} unread',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall,
                ),
                onTap: () =>
                    onLeave(() => MangaRoute(mangaId: m.id).push(context)),
              ),
          ],
        ],
        if (goToHits.isNotEmpty) ...[
          SearchSectionHeader(l.unifiedSearchGoToSection),
          for (final t in goToHits)
            ListTile(
              leading: Icon(t.icon),
              title: Text(t.label(l)),
              onTap: () => onLeave(() => t.navigate(context)),
            ),
        ],
        if (plainQuery.isNotEmpty) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.travel_explore_rounded),
            title: Text(l.unifiedSearchAllSources(plainQuery)),
            onTap: () =>
                onLeave(() => openGlobalSearch(context, query: plainQuery)),
          ),
        ],
      ],
    );
  }
}

/// One Library cover for the phone cover row: ~110 px cover, title below, no
/// source/unread line.
class _PhoneLibraryCoverCard extends StatelessWidget {
  const _PhoneLibraryCoverCard({
    required this.title,
    required this.thumbnailUrl,
    required this.onTap,
  });

  final String title;
  final String? thumbnailUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ServerImage(
              imageUrl: thumbnailUrl ?? '',
              size: const Size(110, 165),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
