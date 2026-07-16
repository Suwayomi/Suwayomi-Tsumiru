// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
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
    useEffect(() {
      var lastText = controller.text;
      void sync() {
        // Only mirror real text edits into the provider. Selection/caret-only
        // changes (e.g. a layout-driven selection clamp) must NOT write state —
        // that could land mid-build and throw. Text only changes from user
        // input or our own setQuery, never during build.
        if (controller.text == lastText) return;
        lastText = controller.text;
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
    final libraryHits = ref.watch(unifiedLibraryResultsProvider);
    final facets = ref.watch(unifiedLibraryFacetsProvider);
    // Same visible set the library tab bar uses: non-empty AND not-hidden.
    final categories =
        ref.watch(visibleCategoryListProvider).value ?? const [];

    final caretRaw = controller.selection.baseOffset;
    final caret = caretRaw < 0 ? controller.text.length : caretRaw;
    final token = activeTokenAt(controller.text, caret);
    final suggestions = suggestFor(token, facets);

    final categoryTargets = [
      for (final c in categories)
        GoToTarget(
          label: (_) => c.name,
          icon: Icons.folder_rounded,
          // .push (not .go) rebuilds LibraryScreen so its DefaultTabController
          // lands on the chosen category — .go reuses the live screen and the
          // tab never changes.
          navigate: (ctx) => LibraryRoute(categoryId: c.id).push(ctx),
        ),
    ];
    final hasQuery = query.trim().isNotEmpty;
    // Global source search only makes sense for the plain-text part — a metatag
    // like `unread:true` is a local filter, not something to ask a source for.
    final plainQuery = plainQueryText(query);
    // Empty query = a launcher of every destination (teaches what's
    // searchable); typing filters it.
    final goToHits = hasQuery
        ? matchGoToTargets(query, l,
            includeHotkeys: isKeyboardRuntime, extra: categoryTargets)
        : [
            ...appGoToTargets(includeHotkeys: isKeyboardRuntime),
            ...categoryTargets,
          ];

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
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l.unifiedSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: InputBorder.none,
                      ),
                      // Enter opens the top result (library first, then go-to),
                      // falling back to the global handoff — not always global.
                      onSubmitted: (_) {
                        if (!hasQuery) return;
                        if (libraryHits.isNotEmpty) {
                          MangaRoute(mangaId: libraryHits.first.id)
                              .push(context);
                        } else if (goToHits.isNotEmpty) {
                          goToHits.first.navigate(context);
                        } else if (plainQuery.isNotEmpty) {
                          GlobalSearchRoute(query: plainQuery).push(context);
                        } else {
                          return; // pure operator query, nothing typed to hand off
                        }
                        close();
                      },
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (!hasQuery) ...[
                          _Header(l.unifiedSearchExamplesSection),
                          for (final ex in _searchExamples)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.bolt_rounded),
                              title: Text(ex),
                              onTap: () => setQuery(ex),
                            ),
                        ],
                        if (suggestions.isNotEmpty) ...[
                          _Header(l.unifiedSearchFiltersSection),
                          for (final s in suggestions)
                            ListTile(
                              dense: true,
                              leading: Icon(s.isKey
                                  ? Icons.data_object_rounded
                                  : Icons.tune_rounded),
                              title: Text(s.display),
                              onTap: () => applyAndStay(s),
                            ),
                        ],
                        if (hasQuery && libraryHits.isNotEmpty) ...[
                          _Header(l.unifiedSearchLibrarySection),
                          for (final m in libraryHits)
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: ServerImage(
                                  imageUrl: m.thumbnailUrl ?? "",
                                  size: const Size(40, 56),
                                ),
                              ),
                              title: Text(m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: _mangaSubtitle(context, m),
                              onTap: () {
                                MangaRoute(mangaId: m.id).push(context);
                                close();
                              },
                            ),
                        ],
                        if (goToHits.isNotEmpty) ...[
                          _Header(l.unifiedSearchGoToSection),
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
                        if (plainQuery.isNotEmpty) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.travel_explore_rounded),
                            title: Text(l.unifiedSearchAllSources(plainQuery)),
                            onTap: () {
                              GlobalSearchRoute(query: plainQuery).push(context);
                              close();
                            },
                          ),
                        ],
                      ],
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

  // Source name + unread count, whichever are present; null when neither.
  Widget? _mangaSubtitle(BuildContext context, MangaDto manga) {
    final source = manga.source?.displayName;
    final parts = [
      if (source != null && source.isNotEmpty) source,
      if (manga.unreadCount > 0) '${manga.unreadCount} unread',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: context.textTheme.labelMedium
                  ?.copyWith(color: context.colorScheme.primary)),
        ),
      );
}
