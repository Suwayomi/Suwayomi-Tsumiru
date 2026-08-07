// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../browse_center/domain/language/flag_emoji.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../domain/migration_models.dart';
import '../widgets/migration_config_sheet.dart';

/// Screen — "Select sources" (Komikku `MigrationConfigScreen`). Chooses and
/// orders the target sources, then opens the data-to-migrate sheet before the
/// migration list. A 1:1 translation of Komikku's flow.
class MigrationBulkConfigScreen extends HookConsumerWidget {
  const MigrationBulkConfigScreen({super.key, required this.mangaIds});

  final List<int> mangaIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allSources = ref.watch(searchableSourcesProvider).value ?? const [];
    final saved = ref.watch(migrationTargetSourcesPrefProvider) ?? const [];

    // Ordered ids of selected sources (seeded from the saved priority, keeping
    // only still-installed ones); everything else is "Available".
    final selectedIds = useState<List<String>>([
      for (final id in saved)
        if (allSources.any((s) => s.id == id)) id,
    ]);
    final query = useState<String>('');

    final byId = {for (final s in allSources) s.id: s};
    bool matches(SourceDto s) {
      final q = query.value.trim().toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || s.id == q;
    }

    final selected = [
      for (final id in selectedIds.value)
        if (byId[id] != null && matches(byId[id]!)) byId[id]!,
    ];
    final available = [
      for (final s in allSources)
        if (!selectedIds.value.contains(s.id) && matches(s)) s,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final showLanguage =
        allSources.map((s) => s.lang).toSet().length > 1;

    void setSelected(Iterable<String> ids) =>
        selectedIds.value = ids.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.migrationSelectSourcesTitle),
        actions: [
          IconButton(
            tooltip: l10n.migrationSelectPinned,
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: () =>
                setSelected([for (final s in allSources) if (s.isPinned) s.id]),
          ),
          IconButton(
            tooltip: l10n.migrationSelectNone,
            icon: const Icon(Icons.deselect),
            onPressed: () => setSelected(const []),
          ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: () => setSelected(
                    [for (final s in allSources) if (!s.isHidden) s.id]),
                child: Text(l10n.migrationSelectEnabled),
              ),
              PopupMenuItem<void>(
                onTap: () => setSelected([for (final s in allSources) s.id]),
                child: Text(l10n.migrationSelectAllSources),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                ref
                    .read(migrationTargetSourcesPrefProvider.notifier)
                    .update(selectedIds.value);
                _openSheet(context, ref);
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(l10n.migrationContinue),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              autofocus: false,
              initialText: query.value,
              hintText: l10n.migrationSearchForSource,
              onChanged: (v) => query.value = v ?? '',
              onClose: () => query.value = '',
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (selected.isNotEmpty) ...[
                  _SectionHeader(l10n.migrationSelectedHeader),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      final list = [...selectedIds.value];
                      if (newIndex > oldIndex) newIndex -= 1;
                      list.insert(newIndex, list.removeAt(oldIndex));
                      selectedIds.value = list;
                    },
                    children: [
                      for (var i = 0; i < selected.length; i++)
                        _SourceCard(
                          key: ValueKey('sel-${selected[i].id}'),
                          source: selected[i],
                          showLanguage: showLanguage,
                          dragIndex: selected.length > 1 ? i : null,
                          onTap: () => setSelected(selectedIds.value
                              .where((id) => id != selected[i].id)),
                        ),
                    ],
                  ),
                ],
                if (available.isNotEmpty) ...[
                  _SectionHeader(l10n.migrationAvailableHeader),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < available.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _SourceCard(
                            source: available[i],
                            showLanguage: showLanguage,
                            dragIndex: null,
                            card: false,
                            onTap: () => setSelected(
                                [...selectedIds.value, available[i].id]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MigrationConfigSheet(
        isSingleEntry: mangaIds.length == 1,
        onStart: (options, extraSearchQuery) {
          Navigator.of(context).pop();
          _start(context, ref, options, extraSearchQuery);
        },
      ),
    );
  }

  void _start(BuildContext context, WidgetRef ref, MigrationRunConfig config,
      String? extraSearchQuery) {
    MigrationBulkRunRoute(
      $extra: MigrationBulkRunData(
        mangaIds: mangaIds,
        targetSourceIds:
            ref.read(migrationTargetSourcesPrefProvider) ?? const [],
        options: MigrationOption(
          migrateChapters: config.migrateChapters,
          migrateCategories: config.migrateCategories,
          migrateTracking: config.migrateTracking,
          migrateReaderSettings: config.migrateReaderSettings,
          migrateOfflineSettings: config.migrateOfflineSettings,
          migrateDownloads: config.migrateDownloads,
          // Copy vs Migrate is chosen on the list screen; default to Migrate.
          deleteSource: true,
        ),
        hideUnmatched: config.hideUnmatched,
        hideWithoutUpdates: config.hideWithoutUpdates,
        extraSearchQuery: extraSearchQuery,
      ),
      // Replace this config screen (Komikku `navigator.replace`) so the run
      // screen pops straight back to the library when migration finishes.
    ).pushReplacement(context);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: context.theme.textTheme.bodyMedium),
      );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.source,
    required this.showLanguage,
    required this.dragIndex,
    required this.onTap,
    this.card = true,
  });

  final SourceDto source;
  final bool showLanguage;
  final int? dragIndex;
  final VoidCallback onTap;

  /// When false, render just the row (for grouping many rows in one card).
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tile = ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: KBorderRadius.r8.radius,
          child: ServerImage(
            imageUrl: source.iconUrl,
            size: const Size.square(40),
          ),
        ),
        title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLanguage)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${flagEmojiForLang(source.lang)} (${source.lang.toUpperCase()})',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (dragIndex != null) ...[
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: dragIndex!,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ],
        ),
    );
    if (!card) return tile;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: tile,
    );
  }
}
