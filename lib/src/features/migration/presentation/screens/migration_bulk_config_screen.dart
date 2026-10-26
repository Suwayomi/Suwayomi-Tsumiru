// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../browse_center/domain/language/flag_emoji.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../domain/migration_models.dart';
import '../widgets/migration_config_sheet.dart';

Set<String> migrationOriginSourceIds(
  Iterable<MangaDto> library,
  List<int> mangaIds,
) => {
  for (final m in library)
    if (mangaIds.contains(m.id)) m.sourceId,
};

String migrationOriginSourceNames(
  Iterable<MangaDto> library,
  List<int> mangaIds,
  Iterable<SourceDto> sources,
  String notInstalledLabel, {
  MangaDto? Function(int mangaId)? mangaLookup,
}) {
  final displayById = {for (final s in sources) s.id: s.displayName};
  final names = <String>[];
  for (final id in mangaIds) {
    MangaDto? manga;
    for (final m in library) {
      if (m.id == id) {
        manga = m;
        break;
      }
    }
    manga ??= mangaLookup?.call(id);
    final embedded = manga?.source?.displayName ?? manga?.source?.name ?? '';
    var name = (embedded.isNotEmpty && embedded != manga?.sourceId)
        ? embedded
        : null;
    name ??= manga == null ? null : displayById[manga.sourceId];
    name ??= notInstalledLabel;
    if (!names.contains(name)) names.add(name);
  }
  return names.join(', ');
}

class MigrationBulkConfigScreen extends HookConsumerWidget {
  const MigrationBulkConfigScreen({super.key, required this.mangaIds});

  final List<int> mangaIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allSources = ref.watch(searchableSourcesProvider).value ?? const [];
    final saved = ref.watch(migrationTargetSourcesPrefProvider) ?? const [];

    final selectedIds = useState<List<String>>([
      for (final id in saved)
        if (allSources.any((s) => s.id == id)) id,
    ]);
    final query = useState<String>('');
    final originIds = migrationOriginSourceIds(
      ref.watch(libraryMangaListProvider).value ?? const [],
      mangaIds,
    );
    final effectiveIds = [
      for (final id in selectedIds.value)
        if (!originIds.contains(id) && allSources.any((s) => s.id == id)) id,
    ];
    final canContinue = allSources.any(
      (s) =>
          effectiveIds.contains(s.id) &&
          (query.value.trim().isEmpty ||
              s.name.toLowerCase().contains(query.value.trim().toLowerCase()) ||
              s.id == query.value.trim().toLowerCase()),
    );
    void setSelected(Iterable<String> ids) => selectedIds.value = ids.toList();
    final topBar = showsMergedTopBar(context);
    final title = Text(l10n.migrationSelectSourcesTitle);
    final actions = <Widget>[
      IconButton(
        tooltip: l10n.migrationSelectPinned,
        icon: const Icon(FluentIcons.pin_24_regular),
        onPressed: () =>
            setSelected([for (final s in allSources) if (s.isPinned) s.id]),
      ),
      IconButton(
        tooltip: l10n.migrationSelectNone,
        icon: const Icon(FluentIcons.select_all_off_24_regular),
        onPressed: () => setSelected(const []),
      ),
      PopupMenuButton<void>(
        icon: const Icon(
          FluentIcons.more_vertical_24_regular,
        ),
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            onTap: () => setSelected(
                [for (final s in allSources) if (!s.isHidden) s.id]),
            child: ChapterMenuRow(
              icon: FluentIcons.checkbox_checked_24_regular,
              label: l10n.migrationSelectEnabled,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => setSelected([for (final s in allSources) s.id]),
            child: ChapterMenuRow(
              icon: FluentIcons.select_all_on_24_regular,
              label: l10n.migrationSelectAllSources,
            ),
          ),
        ],
        popUpAnimationStyle: context.motionStyle,
      ),
    ];
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              actions: actions,
            ),
      floatingActionButton: !canContinue
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                ref
                    .read(migrationTargetSourcesPrefProvider.notifier)
                    .update(selectedIds.value);
                _openSheet(context, ref, effectiveIds);
              },
              icon: const Icon(FluentIcons.arrow_right_24_regular),
              label: Text(l10n.migrationContinue),
            ),
      body: MigrationTargetSourcePicker(
        selectedIds: selectedIds,
        query: query,
        excludedSourceIds: originIds,
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      actions: actions,
      child: scaffold,
    );
  }

  void _openSheet(
      BuildContext context, WidgetRef ref, List<String> targetSourceIds) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MigrationConfigSheet(
        isSingleEntry: mangaIds.length == 1,
        onStart: (options, extraSearchQuery) {
          Navigator.of(context).pop();
          _start(context, ref, options, extraSearchQuery, targetSourceIds);
        },
      ),
      sheetAnimationStyle: context.motionStyle,
    );
  }

  Future<void> _start(
      BuildContext context,
      WidgetRef ref,
      MigrationRunConfig config,
      String? extraSearchQuery,
      List<String> targetSourceIds) async {
    final result = await MigrationBulkRunRoute(
      $extra: MigrationBulkRunData(
        mangaIds: mangaIds,
        targetSourceIds: targetSourceIds,
        options: config.toOption(deleteSource: true),
        hideUnmatched: config.hideUnmatched,
        hideWithoutUpdates: config.hideWithoutUpdates,
        extraSearchQuery: extraSearchQuery,
      ),
    ).push<Object?>(context);
    if (context.mounted) Navigator.of(context).pop(result);
  }
}

class MigrationTargetSourcePicker extends HookConsumerWidget {
  const MigrationTargetSourcePicker({
    super.key,
    required this.selectedIds,
    this.desktop = false,
    this.query,
    this.excludedSourceIds = const {},
  });

  final ValueNotifier<List<String>> selectedIds;
  final bool desktop;
  final ValueNotifier<String>? query;

  /// Origin sources of the migrating series: kept in selection, never listed.
  final Set<String> excludedSourceIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useValueListenable(selectedIds);
    final l10n = context.l10n;
    final allSources = ref.watch(searchableSourcesProvider).value ?? const [];
    final localQuery = useState<String>('');
    final query = this.query ?? localQuery;

    final byId = {for (final s in allSources) s.id: s};
    bool matches(SourceDto s) {
      final q = query.value.trim().toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || s.id == q;
    }

    final selected = [
      for (final id in selectedIds.value)
        if (byId[id] != null &&
            !excludedSourceIds.contains(id) &&
            matches(byId[id]!))
          byId[id]!,
    ];
    final available = [
      for (final s in allSources)
        if (!selectedIds.value.contains(s.id) &&
            !excludedSourceIds.contains(s.id) &&
            matches(s))
          s,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final showLanguage = allSources.map((s) => s.lang).toSet().length > 1;

    void setSelected(Iterable<String> ids) => selectedIds.value = ids.toList();
    return Column(
      children: [
        if (desktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(l10n.migrationSelectPinned),
                  onPressed: () => setSelected([
                    for (final s in allSources)
                      if (s.isPinned) s.id,
                  ]),
                ),
                ActionChip(
                  label: Text(l10n.migrationSelectEnabled),
                  onPressed: () => setSelected([
                    for (final s in allSources)
                      if (!s.isHidden) s.id,
                  ]),
                ),
                ActionChip(
                  label: Text(l10n.migrationSelectAllSources),
                  onPressed: () =>
                      setSelected([for (final s in allSources) s.id]),
                ),
                ActionChip(
                  label: Text(l10n.migrationSelectNone),
                  onPressed: () => setSelected(const []),
                ),
              ],
            ),
          ),
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
                  onReorderItem: (oldIndex, newIndex) {
                    if (oldIndex == newIndex) return;
                    final list = [...selectedIds.value];
                    final moved = selected[oldIndex].id;
                    list.remove(moved);
                    final target = list.indexOf(selected[newIndex].id);
                    list.insert(target + (newIndex > oldIndex ? 1 : 0), moved);
                    selectedIds.value = list;
                  },
                  children: [
                    for (var i = 0; i < selected.length; i++)
                      _SourceCard(
                        key: ValueKey('sel-${selected[i].id}'),
                        source: selected[i],
                        checked: desktop ? true : null,
                        showLanguage: showLanguage,
                        dragIndex: selected.length > 1 ? i : null,
                        onTap: () => setSelected(
                          selectedIds.value.where((id) => id != selected[i].id),
                        ),
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
                          checked: desktop ? false : null,
                          showLanguage: showLanguage,
                          dragIndex: null,
                          card: false,
                          onTap: () => setSelected([
                            ...selectedIds.value,
                            available[i].id,
                          ]),
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
    );
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
    this.checked,
  });

  final SourceDto source;
  final bool showLanguage;
  final int? dragIndex;
  final VoidCallback onTap;

  final bool card;
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tile = ListTile(
      onTap: onTap,
      selected: checked == true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checked != null)
            Checkbox(value: checked, onChanged: (_) => onTap()),
          ClipRRect(
            borderRadius: KBorderRadius.r8.radius,
            child: ServerImage(
              imageUrl: source.iconUrl,
              size: const Size.square(40),
            ),
          ),
        ],
      ),
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLanguage && source.lang.toLowerCase() != 'localsourcelang')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                child: Icon(FluentIcons.re_order_24_regular),
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
