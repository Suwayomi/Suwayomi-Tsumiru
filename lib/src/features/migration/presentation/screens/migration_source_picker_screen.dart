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
import '../../../../constants/enum.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../controller/migration_source_preferences.dart';
import '../../domain/migration_models.dart';
import 'migration_window.dart';

class MigrationSourcePickerScreen extends StatelessWidget {
  const MigrationSourcePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.migrationPickSourceTitle);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
            ),
      body: const MigrationSourcePickerBody(),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}

class MigrationSourcePickerBody extends HookConsumerWidget {
  const MigrationSourcePickerBody({
    super.key,
    this.hideInnerSearchOnDesktop = false,
  });

  /// Browse supplies the desktop search box; standalone routes retain their own.
  final bool hideInnerSearchOnDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final groupsAsync = ref.watch(librarySourceGroupsProvider);
    final sources = ref.watch(searchableSourcesProvider).value ?? const [];
    final iconById = {for (final s in sources) s.id: s.iconUrl};

    final query = ref.watch(migrationSourcePickerQueryProvider);
    final searchController = useTextEditingController(text: query);
    final preferences = (
      sort: ref.watch(migrationSourceSortProvider),
      ascending: ref.watch(migrationSourceAscendingProvider) ?? true,
      obsoleteOnly: ref.watch(migrationSourceObsoleteOnlyProvider) ?? false,
    );
    final setSort = ref.read(migrationSourceSortProvider.notifier).update;
    final setAscending =
        ref.read(migrationSourceAscendingProvider.notifier).update;
    final setObsoleteOnly =
        ref.read(migrationSourceObsoleteOnlyProvider.notifier).update;
    final selectedSource = useState<String?>(null);
    final desktop = context.usesDesktopShell;
    String sourceName(String id, String name) =>
        name == id ? l10n.migrationSourceNotInstalled : name;

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final q = query.trim().toLowerCase();
        final noObsoleteSources =
            preferences.obsoleteOnly && !all.any((g) => g.isObsolete);
        var groups = [
          for (final g in all)
            if ((!preferences.obsoleteOnly || g.isObsolete) &&
                (q.isEmpty ||
                    sourceName(
                      g.sourceId,
                      g.displayName,
                    ).toLowerCase().contains(q)))
              g,
        ];
        groups = [...groups]
          ..sort((a, b) {
            final c = preferences.sort == MigrationSourceSort.alphabetical
                ? sourceName(a.sourceId, a.displayName).toLowerCase().compareTo(
                    sourceName(b.sourceId, b.displayName).toLowerCase(),
                  )
                : a.count.compareTo(b.count);
            return preferences.ascending ? c : -c;
          });
        if (all.isEmpty) {
          return Center(child: Text(l10n.migrationNoLibrarySources));
        }
        final selected =
            groups
                .where((g) => g.sourceId == selectedSource.value)
                .firstOrNull ??
            groups.firstOrNull;
        final sourceList = Column(
          children: [
            if (desktop)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: DesktopToolbarBox(
                        child: PopupMenuButton<MigrationSourceSort>(
                          tooltip: l10n.migrationSortMode,
                          initialValue: preferences.sort,
                          onSelected: setSort,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: MigrationSourceSort.alphabetical,
                              child: Text(l10n.mangaSortAlphabetical),
                            ),
                            PopupMenuItem(
                              value: MigrationSourceSort.total,
                              child: Text(l10n.migrationSortCount),
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    preferences.sort ==
                                            MigrationSourceSort.alphabetical
                                        ? l10n.mangaSortAlphabetical
                                        : l10n.migrationSortCount,
                                  ),
                                ),
                                const Icon(
                                  FluentIcons.chevron_down_24_regular,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.migrationSortDirection,
                      icon: Icon(
                        preferences.ascending
                            ? FluentIcons.arrow_sort_up_24_regular
                            : FluentIcons.arrow_sort_down_24_regular,
                      ),
                      onPressed: () =>
                          setAscending(!preferences.ascending),
                    ),
                    IconButton(
                      tooltip: l10n.migrationFilterObsolete,
                      isSelected: preferences.obsoleteOnly,
                      color: preferences.obsoleteOnly
                          ? context.colorScheme.error
                          : null,
                      icon: const Icon(FluentIcons.warning_24_regular),
                      onPressed: () =>
                          setObsoleteOnly(!preferences.obsoleteOnly),
                    ),
                  ],
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l10n.migrationFilterObsolete,
                    icon: const Icon(FluentIcons.warning_24_regular),
                    color: preferences.obsoleteOnly
                        ? context.colorScheme.error
                        : null,
                    onPressed: () =>
                        setObsoleteOnly(!preferences.obsoleteOnly),
                  ),
                  IconButton(
                    tooltip: l10n.migrationSortMode,
                    icon: Icon(
                      preferences.sort == MigrationSourceSort.alphabetical
                          ? FluentIcons.text_sort_ascending_24_regular
                          : FluentIcons.number_symbol_24_regular,
                    ),
                    onPressed: () => setSort(
                      preferences.sort == MigrationSourceSort.alphabetical
                          ? MigrationSourceSort.total
                          : MigrationSourceSort.alphabetical,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.migrationSortDirection,
                    icon: Icon(
                      preferences.ascending
                          ? FluentIcons.arrow_sort_up_24_regular
                          : FluentIcons.arrow_sort_down_24_regular,
                    ),
                    onPressed: () =>
                        setAscending(!preferences.ascending),
                  ),
                ],
              ),
            if (!hideInnerSearchOnDesktop || !context.usesDesktopShell)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchField(
                  autofocus: false,
                  controller: searchController,
                  hintText: l10n.migrationSearchForSource,
                  onChanged: (v) => ref
                      .read(migrationSourcePickerQueryProvider.notifier)
                      .update(v ?? ''),
                  onClose: () => ref
                      .read(migrationSourcePickerQueryProvider.notifier)
                      .update(''),
                ),
              ),
            if (groups.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        noObsoleteSources
                            ? l10n.migrationNoObsoleteSources
                            : l10n.noSearchResults,
                      ),
                      TextButton(
                        onPressed: () {
                          if (noObsoleteSources) {
                            setObsoleteOnly(false);
                          } else {
                            searchController.clear();
                            ref
                                .read(migrationSourcePickerQueryProvider.notifier)
                                .update('');
                          }
                        },
                        child: Text(
                          noObsoleteSources
                              ? l10n.migrationShowAllSources
                              : l10n.migrationClearSearch,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final g = groups[i];
                    return ListTile(
                      selected: desktop && selected?.sourceId == g.sourceId,
                      selectedTileColor: context.colorScheme.primaryContainer,
                      leading: ClipRRect(
                        borderRadius: KBorderRadius.r8.radius,
                        child: ServerImage(
                          imageUrl: iconById[g.sourceId] ?? '',
                          size: const Size.square(40),
                        ),
                      ),
                      title: Text(sourceName(g.sourceId, g.displayName)),
                      subtitle: g.isObsolete
                          ? Text(
                              g.displayName == g.sourceId
                                  ? '${l10n.migrationObsoleteSource} · ${g.sourceId}'
                                  : l10n.migrationObsoleteSource,
                              style: TextStyle(
                                color: context.theme.colorScheme.error,
                              ),
                            )
                          : null,
                      trailing: _CountBadge(g.count),
                      onTap: desktop
                          ? () => selectedSource.value = g.sourceId
                          : () => MigrationSourceMangaRoute(
                              $extra: MigrationSourceMangaData(
                                sourceId: g.sourceId,
                                sourceName: sourceName(g.sourceId, g.displayName),
                              ),
                            ).push(context),
                    );
                  },
                ),
              ),
          ],
        );
        if (!desktop) return sourceList;
        return Row(
          children: [
            SizedBox(width: 340, child: sourceList),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const SizedBox.shrink()
                  : _DesktopSourceSeries(
                      key: ValueKey(selected.sourceId),
                      sourceId: selected.sourceId,
                      sourceName: sourceName(
                        selected.sourceId,
                        selected.displayName,
                      ),
                      iconUrl: iconById[selected.sourceId] ?? '',
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

List<MangaDto> sourceMangasByTitle(
  Iterable<MangaDto>? library,
  String sourceId,
) {
  final mangas = <MangaDto>[
    for (final m in library ?? const <MangaDto>[])
      if (m.sourceId == sourceId) m,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return mangas;
}

List<MangaDto> filterMangasByTitle(List<MangaDto> mangas, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return mangas;
  return <MangaDto>[
    for (final m in mangas)
      if (m.title.toLowerCase().contains(q)) m,
  ];
}

Set<int> toggledSelection(Set<int> selection, int id) {
  final next = {...selection};
  next.contains(id) ? next.remove(id) : next.add(id);
  return next;
}

class MigrationSourceMangaScreen extends HookConsumerWidget {
  const MigrationSourceMangaScreen({super.key, required this.data});

  final MigrationSourceMangaData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final library = ref.watch(libraryMangaListProvider);
    final mangas = sourceMangasByTitle(library.value, data.sourceId);
    final selection = useState<Set<int>>({});
    final selecting = selection.value.isNotEmpty;
    final searching = useState(false);
    final query = useState('');
    final searchController = useTextEditingController();
    final q = query.value.trim().toLowerCase();
    final visible = filterMangasByTitle(mangas, query.value);

    void toggle(int id) =>
        selection.value = toggledSelection(selection.value, id);

    final topBar = showsMergedTopBar(context);
    final closeSelection = IconButton(
      icon: const Icon(FluentIcons.dismiss_24_regular),
      onPressed: () => selection.value = const {},
    );
    final title = searching.value
        ? SearchField(
            controller: searchController,
            hintText: l10n.search,
            onChanged: (v) => query.value = v ?? '',
            onClose: () {
              query.value = '';
              searching.value = false;
            },
          )
        : Text(selecting ? '${selection.value.length}' : data.sourceName);
    final actions = <Widget>[
      if (!searching.value)
        IconButton(
          tooltip: l10n.search,
          icon: const Icon(FluentIcons.search_24_regular),
          onPressed: () => searching.value = true,
        ),
      IconButton(
        tooltip: l10n.migrationSelectAllSources,
        icon: const Icon(FluentIcons.select_all_on_24_regular),
        onPressed: () => selection.value = {for (final m in visible) m.id},
      ),
      if (selecting)
        IconButton(
          tooltip: l10n.migrationInvertSelection,
          icon: const Icon(FluentIcons.arrow_swap_24_regular),
          onPressed: () => selection.value = {
            for (final m in visible)
              if (!selection.value.contains(m.id)) m.id,
          },
        ),
    ];
    final scaffold = Scaffold(
      appBar: selecting
          ? (topBar
                ? null
                : AppBar(
                    leading: closeSelection,
                    title: title,
                    actions: actions,
                  ))
          : topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              actions: actions,
            ),
      body: library.isLoading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty && q.isNotEmpty
              ? Center(child: Text(l10n.noSearchResults))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final m = visible[i];
                    final checked = selection.value.contains(m.id);
                    return ListTile(
                      selected: checked,
                      leading: ClipRRect(
                        borderRadius: KBorderRadius.r8.radius,
                        child: ServerImage(
                          imageUrl: m.displayCoverUrl,
                          fallbackImageUrl: m.thumbnailUrl,
                          coverVersion: m.coverVersion,
                          fallbackCoverVersion: m.thumbnailUrlLastFetched,
                          size: const Size.square(40),
                        ),
                      ),
                      title: Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: checked
                          ? const Icon(
                              FluentIcons.checkmark_circle_24_filled,
                            )
                          : null,
                      onTap: () {
                        if (selecting) {
                          toggle(m.id);
                        } else {
                          startMigration(context, mangaIds: [m.id]);
                        }
                      },
                      onLongPress: () => toggle(m.id),
                    );
                  },
                ),
      bottomNavigationBar: selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => startMigration(
                    context,
                    mangaIds: selection.value.toList(),
                  ),
                  icon: const Icon(FluentIcons.arrow_swap_24_regular),
                  label: Text(l10n.migrate),
                ),
              ),
            )
          : null,
    );
    if (!topBar) return scaffold;
    if (selecting) {
      return TopBarSlot(
        slotKey: 'selection',
        content: DesktopTitleSlot(
          leading: closeSelection,
          title: title,
          actions: actions,
        ),
        minWidth: titleTopBarSlotMinWidth(actions.length),
        child: scaffold,
      );
    }
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      actions: actions,
      child: scaffold,
    );
  }
}

class _DesktopSourceSeries extends HookConsumerWidget {
  const _DesktopSourceSeries({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.iconUrl,
  });

  final String sourceId;
  final String sourceName;
  final String iconUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryMangaListProvider);
    final mangas = sourceMangasByTitle(library.value, sourceId);
    final selection = useState<Set<int>>({});
    final searchController = useTextEditingController();
    final query = useState('');
    final q = query.value.trim().toLowerCase();
    final visible = filterMangasByTitle(mangas, query.value);
    final selectedIds = <int>[
      for (final m in mangas)
        if (selection.value.contains(m.id)) m.id,
    ];
    void toggle(int id) =>
        selection.value = toggledSelection(selection.value, id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ServerImage(imageUrl: iconUrl, size: const Size.square(32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.migrationSeriesCount(visible.length),
                style: context.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SearchField(
                  autofocus: false,
                  controller: searchController,
                  hintText: context.l10n.search,
                  onChanged: (v) => query.value = v ?? '',
                  onClose: () => query.value = '',
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    selection.value = {for (final m in visible) m.id},
                child: Text(context.l10n.migrationSelectAllSources),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () async {
                        await startMigration(
                          context,
                          mangaIds: selectedIds,
                        );
                        if (!context.mounted) return;
                        selection.value = {};
                      },
                child: Text(
                  context.l10n.migrateSeriesCount(selectedIds.length),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty && q.isNotEmpty
              ? Center(child: Text(context.l10n.noSearchResults))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: (visible.length / 2).ceil(),
                  itemBuilder: (context, row) => Row(
                    children: [
                      for (var column = 0; column < 2; column++)
                        Expanded(
                          child: row * 2 + column >= visible.length
                              ? const SizedBox.shrink()
                              : Builder(
                                  builder: (context) {
                                    final m = visible[row * 2 + column];
                                    final checked = selection.value.contains(
                                      m.id,
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Material(
                                        color: checked
                                            ? context
                                                  .colorScheme
                                                  .primaryContainer
                                            : context.colorScheme.surface,
                                        borderRadius: KBorderRadius.r8.radius,
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () => toggle(m.id),
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                  horizontal: 4,
                                                ),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  value: checked,
                                                  onChanged: (_) =>
                                                      toggle(m.id),
                                                ),
                                                ClipRRect(
                                                  borderRadius:
                                                      KBorderRadius.r8.radius,
                                                  child: ServerImage(
                                                    imageUrl:
                                                        m.displayCoverUrl,
                                                    fallbackImageUrl:
                                                        m.thumbnailUrl,
                                                    coverVersion:
                                                        m.coverVersion,
                                                    fallbackCoverVersion: m
                                                        .thumbnailUrlLastFetched,
                                                    size: const Size(40, 56),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        m.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        context.l10n.noOfChapters(
                                                          m.chapters.totalCount,
                                                        ),
                                                        style: context
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
