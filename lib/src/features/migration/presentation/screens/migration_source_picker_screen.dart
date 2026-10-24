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
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../domain/migration_models.dart';

enum _SortMode { alphabetical, total }

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
    final obsoleteOnly = useState(false);
    final sortMode = useState(_SortMode.alphabetical);
    final ascending = useState(true);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final q = query.trim().toLowerCase();
        var groups = [
          for (final g in all)
            if ((!obsoleteOnly.value || g.isObsolete) &&
                (q.isEmpty || g.displayName.toLowerCase().contains(q)))
              g,
        ];
        groups = [...groups]
          ..sort((a, b) {
            final c = sortMode.value == _SortMode.alphabetical
                ? a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  )
                : a.count.compareTo(b.count);
            return ascending.value ? c : -c;
          });
        if (all.isEmpty) {
          return Center(child: Text(l10n.migrationNoLibrarySources));
        }
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: l10n.migrationFilterObsolete,
                  icon: const Icon(FluentIcons.warning_24_regular),
                  color: obsoleteOnly.value
                      ? context.theme.colorScheme.error
                      : null,
                  onPressed: () => obsoleteOnly.value = !obsoleteOnly.value,
                ),
                IconButton(
                  tooltip: l10n.migrationSortMode,
                  icon: Icon(
                    sortMode.value == _SortMode.alphabetical
                        ? FluentIcons.text_sort_ascending_24_regular
                        : FluentIcons.number_symbol_24_regular,
                  ),
                  onPressed: () =>
                      sortMode.value = sortMode.value == _SortMode.alphabetical
                      ? _SortMode.total
                      : _SortMode.alphabetical,
                ),
                IconButton(
                  tooltip: l10n.migrationSortDirection,
                  icon: Icon(
                    ascending.value ? FluentIcons.arrow_sort_up_24_regular : FluentIcons.arrow_sort_down_24_regular,
                  ),
                  onPressed: () => ascending.value = !ascending.value,
                ),
              ],
            ),
            if (!hideInnerSearchOnDesktop || !context.usesDesktopShell)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchField(
                  autofocus: false,
                  initialText: query,
                  hintText: l10n.migrationSearchForSource,
                  onChanged: (v) => ref
                      .read(migrationSourcePickerQueryProvider.notifier)
                      .update(v ?? ''),
                  onClose: () => ref
                      .read(migrationSourcePickerQueryProvider.notifier)
                      .update(''),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, i) {
                  final g = groups[i];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: KBorderRadius.r8.radius,
                      child: ServerImage(
                        imageUrl: iconById[g.sourceId] ?? '',
                        size: const Size.square(40),
                      ),
                    ),
                    title: Text(g.displayName),
                    subtitle: g.isObsolete
                        ? Text(
                            l10n.migrationObsoleteSource,
                            style: TextStyle(
                              color: context.theme.colorScheme.error,
                            ),
                          )
                        : null,
                    trailing: _CountBadge(g.count),
                    onTap: () => MigrationSourceMangaRoute(
                      $extra: MigrationSourceMangaData(
                        sourceId: g.sourceId,
                        sourceName: g.displayName,
                      ),
                    ).push(context),
                  );
                },
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

class MigrationSourceMangaScreen extends HookConsumerWidget {
  const MigrationSourceMangaScreen({super.key, required this.data});

  final MigrationSourceMangaData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final library = ref.watch(libraryMangaListProvider);
    final mangas = [
      for (final m in library.value ?? const [])
        if (m.sourceId == data.sourceId) m,
    ];
    final selection = useState<Set<int>>({});
    final selecting = selection.value.isNotEmpty;

    void toggle(int id) {
      final next = {...selection.value};
      next.contains(id) ? next.remove(id) : next.add(id);
      selection.value = next;
    }

    final topBar = showsMergedTopBar(context);
    final closeSelection = IconButton(
      icon: const Icon(FluentIcons.dismiss_24_regular),
      onPressed: () => selection.value = const {},
    );
    final title = Text(
      selecting ? '${selection.value.length}' : data.sourceName,
    );
    final actions = <Widget>[
      IconButton(
        tooltip: l10n.migrationSelectAllSources,
        icon: const Icon(FluentIcons.select_all_on_24_regular),
        onPressed: () => selection.value = {for (final m in mangas) m.id},
      ),
      if (selecting)
        IconButton(
          tooltip: l10n.migrationInvertSelection,
          icon: const Icon(FluentIcons.arrow_swap_24_regular),
          onPressed: () => selection.value = {
            for (final m in mangas)
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
          : ListView.builder(
              itemCount: mangas.length,
              itemBuilder: (context, i) {
                final m = mangas[i];
                final checked = selection.value.contains(m.id);
                return ListTile(
                  selected: checked,
                  leading: ClipRRect(
                    borderRadius: KBorderRadius.r8.radius,
                    child: ServerImage(
                      imageUrl: m.thumbnailUrl ?? '',
                      size: const Size.square(40),
                    ),
                  ),
                  title: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: checked ? const Icon(FluentIcons.checkmark_circle_24_filled) : null,
                  onTap: () {
                    if (selecting) {
                      toggle(m.id);
                    } else {
                      MigrationBulkConfigRoute(
                        $extra: MigrationBulkConfigData(mangaIds: [m.id]),
                      ).push(context);
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
                  onPressed: () => MigrationBulkConfigRoute(
                    $extra: MigrationBulkConfigData(
                      mangaIds: selection.value.toList(),
                    ),
                  ).push(context),
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
