// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_window.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../domain/migration_models.dart';
import '../widgets/migration_config_sheet.dart';
import 'migration_bulk_config_screen.dart';
import 'migration_bulk_run_screen.dart';

Future<void> showMigrationWindow(
  BuildContext context, {
  required List<int> mangaIds,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    pageBuilder: (context, _, _) => DesktopWindow(
      onClose: () => Navigator.of(context).pop(),
      child: _MigrationWindow(mangaIds: mangaIds),
    ),
  );
  container.invalidate(libraryMangaListProvider);
  container.invalidate(librarySourceGroupsProvider);
}

Future<void> startMigration(
  BuildContext context, {
  required List<int> mangaIds,
}) async {
  if (mangaIds.isEmpty) return;
  if (context.usesDesktopShell) {
    await showMigrationWindow(context, mangaIds: mangaIds);
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  await MigrationBulkConfigRoute(
    $extra: MigrationBulkConfigData(mangaIds: mangaIds),
  ).push(context);
  container.invalidate(libraryMangaListProvider);
  container.invalidate(librarySourceGroupsProvider);
}

class _MigrationWindow extends HookConsumerWidget {
  const _MigrationWindow({required this.mangaIds});

  final List<int> mangaIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(migrationTargetSourcesPrefProvider) ?? const [];
    final selected = useState<List<String>>([...saved]);
    final config = useState(MigrationRunConfig.defaults);
    final extraSearch = useTextEditingController();
    final run = useState<MigrationBulkRunData?>(null);
    final allSources = ref.watch(searchableSourcesProvider).value ?? const [];
    final library = ref.watch(libraryMangaListProvider).value ?? const [];
    final originIds = migrationOriginSourceIds(library, mangaIds);
    final lookups = {
      for (final id in mangaIds)
        if (!library.any((m) => m.id == id))
          id: ref.watch(mangaWithIdProvider(mangaId: id)).value,
    };
    final sourceNames = migrationOriginSourceNames(
      library,
      mangaIds,
      allSources,
      l10n.migrationSourceNotInstalled,
      mangaLookup: (id) => lookups[id],
    );
    final targetIds = [
      for (final id in selected.value)
        if (allSources.any((s) => s.id == id)) id,
    ];
    final effectiveTargetIds = [
      for (final id in targetIds)
        if (!originIds.contains(id)) id,
    ];
    void close() => Navigator.of(context).pop();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.migrateSeriesCount(mangaIds.length),
                  style: context.textTheme.titleLarge,
                ),
              ),
              _Step(
                number: 1,
                label: l10n.migrationSourcesAndOptions,
                active: run.value == null,
              ),
              const SizedBox(width: 24),
              _Step(
                number: 2,
                label: l10n.migrationReviewMatches,
                active: run.value != null,
              ),
              const SizedBox(width: 24),
              IconButton(
                tooltip: l10n.close,
                onPressed: close,
                icon: const Icon(FluentIcons.dismiss_24_regular),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: run.value != null
              ? MigrationBulkRunBody(
                  data: run.value!,
                  onBack: () => run.value = null,
                  onFinished: close,
                  windowed: true,
                )
              : Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: MigrationTargetSourcePicker(
                              selectedIds: selected,
                              desktop: true,
                              excludedSourceIds: originIds,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: MigrationConfigOptions(
                                config: config.value,
                                onChanged: (value) => config.value = value,
                                extraSearch: extraSearch,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sourceNames.isEmpty
                                  ? l10n.migrationSeriesCount(
                                      mangaIds.length,
                                    )
                                  : l10n.migrationSeriesFromSource(
                                      mangaIds.length,
                                      sourceNames,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: close,
                            child: Text(
                              MaterialLocalizations.of(
                                context,
                              ).cancelButtonLabel,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: effectiveTargetIds.isEmpty
                                ? null
                                : () {
                                    ref
                                        .read(
                                          migrationTargetSourcesPrefProvider
                                              .notifier,
                                        )
                                        .update(targetIds);
                                    final options = config.value;
                                    final query = extraSearch.text.trim();
                                    run.value = MigrationBulkRunData(
                                      mangaIds: mangaIds,
                                      targetSourceIds: effectiveTargetIds,
                                      options: options.toOption(
                                        deleteSource: true,
                                      ),
                                      hideUnmatched: options.hideUnmatched,
                                      hideWithoutUpdates:
                                          options.hideWithoutUpdates,
                                      extraSearchQuery: query.isEmpty
                                          ? null
                                          : query,
                                    );
                                  },
                            child: Text(l10n.migrationContinue),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.label,
    required this.active,
  });

  final int number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 11,
        backgroundColor: active
            ? context.colorScheme.primary
            : context.colorScheme.surfaceContainerHighest,
        foregroundColor: active
            ? context.colorScheme.onPrimary
            : context.colorScheme.onSurfaceVariant,
        child: Text(
          '$number',
          style: context.textTheme.labelSmall?.copyWith(
            color: active
                ? context.colorScheme.onPrimary
                : context.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: context.textTheme.labelMedium?.copyWith(
          color: active
              ? context.colorScheme.onSurface
              : context.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
