// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import 'go_to_targets.dart';
import 'unified_search_providers.dart';

class UnifiedSearchScreen extends ConsumerWidget {
  const UnifiedSearchScreen({super.key, required this.afterClick});

  final VoidCallback afterClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final query = ref.watch(unifiedSearchQueryProvider);
    final libraryHits = ref.watch(unifiedLibraryResultsProvider);
    final categories =
        ref.watch(categoryControllerProvider).valueOrNull ?? const [];

    final categoryTargets = [
      for (final c in categories)
        GoToTarget(
          label: (_) => c.name,
          icon: Icons.folder_rounded,
          navigate: (ctx) => LibraryRoute(categoryId: c.id).go(ctx),
        ),
    ];
    final goToHits = matchGoToTargets(query, l,
        includeHotkeys: isKeyboardRuntime, extra: categoryTargets);
    final hasQuery = query.trim().isNotEmpty;

    void close() => afterClick();

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
            constraints: const BoxConstraints(maxWidth: 640),
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
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l.unifiedSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => ref
                          .read(unifiedSearchQueryProvider.notifier)
                          .state = v,
                      // Enter opens the top result (library first, then go-to),
                      // falling back to the global handoff — not always global.
                      onSubmitted: (_) {
                        if (!hasQuery) return;
                        if (libraryHits.isNotEmpty) {
                          MangaRoute(mangaId: libraryHits.first.id)
                              .push(context);
                        } else if (goToHits.isNotEmpty) {
                          goToHits.first.navigate(context);
                        } else {
                          GlobalSearchRoute(query: query).push(context);
                        }
                        close();
                      },
                    ),
                  ),
                  if (hasQuery)
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (libraryHits.isNotEmpty) ...[
                            _Header(l.unifiedSearchLibrarySection),
                            for (final m in libraryHits)
                              ListTile(
                                leading: const Icon(Icons.book_rounded),
                                title: Text(m.title),
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
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.travel_explore_rounded),
                            title: Text(l.unifiedSearchAllSources(query)),
                            onTap: () {
                              GlobalSearchRoute(query: query).push(context);
                              close();
                            },
                          ),
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
