// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/server_image.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../data/bulk_migration_runner.dart';
import '../../domain/bulk_migration_types.dart';
import '../../domain/migration_models.dart';
import '../widgets/migration_config_sheet.dart';

/// Migration list (Komikku `MigrationListScreen`). Each row compares the source
/// manga to its matched target as cover cards; Copy / Migrate live in the top
/// bar; the per-row ⋮ menu offers search-manually / skip / migrate-now / copy-now.
class MigrationBulkRunScreen extends HookConsumerWidget {
  const MigrationBulkRunScreen({super.key, required this.data});

  final MigrationBulkRunData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final library = ref.watch(libraryMangaListProvider);
    final runner = useState<BulkMigrationRunner?>(null);
    final hideUnmatched = useState(data.hideUnmatched);
    final hideWithoutUpdates = useState(data.hideWithoutUpdates);

    final sourceById = {for (final m in library.value ?? const []) m.id: m};
    // Resolve in the build body (listen:false) — calling containerOf inside
    // useEffect runs during hook-init, where inherited-widget lookups throw.
    final container = ProviderScope.containerOf(context, listen: false);

    useEffect(() {
      if (runner.value != null) return null;
      final mangas = library.value;
      if (mangas == null) return null;
      final byId = {for (final m in mangas) m.id: m};
      final entries = [
        for (final id in data.mangaIds)
          if (byId[id] != null)
            BulkMigrationEntry(
              fromMangaId: id,
              fromTitle: byId[id]!.title,
              fromThumbnailUrl: byId[id]!.thumbnailUrl,
              fromSourceName: byId[id]!.source?.displayName,
              fromChapterCount: byId[id]!.chapters.totalCount,
            ),
      ];
      final r = buildBulkMigrationRunner(
        container: container,
        entries: entries,
        targetSourceIds: data.targetSourceIds,
        options: data.options,
        extraSearchQuery: data.extraSearchQuery,
        onSourceRemoved: (id) => reconcileMangaWidget(ref, id),
      );
      runner.value = r;
      final repo = ref.read(mangaBookRepositoryProvider);
      Future(() async {
        for (final e in entries) {
          e.fromLatestChapter = await _latestChapter(repo, e.fromMangaId);
        }
        r.notify();
        await r.search();
        await r.preflight();
        for (final e in r.entries) {
          final toId = e.toMangaId;
          if (toId == null) continue;
          final chapters = await repo.getChapterList(toId);
          e.toChapterCount = chapters?.length ?? 0;
          e.toLatestChapter = _latestOf(chapters);
        }
        r.notify();
      });
      return r.cancel;
    }, [library]);

    final r = runner.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null || r.entries.isEmpty
            ? l10n.migrationListTitle
            : l10n.migrationListTitleProgress(_finished(r), r.entries.length)),
        actions: r == null
            ? null
            : [
                AnimatedBuilder(
                  animation: r,
                  builder: (context, _) {
                    final complete = _complete(r);
                    final single = r.entries.length == 1;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.migrationSettings,
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => _openSettings(
                              context, r, hideUnmatched, hideWithoutUpdates),
                        ),
                        IconButton(
                          tooltip: l10n.migrationActionCopy,
                          icon: Icon(single
                              ? Icons.content_copy_outlined
                              : Icons.copy_all_outlined),
                          onPressed: complete
                              ? () => _confirm(context, r, deleteSource: false)
                              : null,
                        ),
                        IconButton(
                          tooltip: l10n.migrationActionMigrate,
                          icon: Icon(
                              single ? Icons.done_outlined : Icons.done_all_outlined),
                          onPressed: complete
                              ? () => _confirm(context, r, deleteSource: true)
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ],
      ),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: r,
              builder: (context, _) {
                final visible = [
                  for (final e in r.entries)
                    if (!(hideUnmatched.value &&
                            e.phase == BulkEntryPhase.noMatch) &&
                        !(hideWithoutUpdates.value && _noUpdates(e)))
                      e,
                ];
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _Row(
                    entry: visible[i],
                    runner: r,
                    onSearchManually: () => _searchManually(context, r,
                        visible[i].fromMangaId, sourceById[visible[i].fromMangaId]),
                    onCommitRow: (deleteSource) => _commitRow(
                        context, r, visible[i].fromMangaId,
                        deleteSource: deleteSource),
                  ),
                );
              },
            ),
    );
  }

  /// A matched target with no more chapters than the source — hidden by the
  /// "hide without updates" toggle.
  bool _noUpdates(BulkMigrationEntry e) {
    if (e.toMangaId == null) return false;
    final from = e.fromLatestChapter;
    final to = e.toLatestChapter;
    if (from == null || to == null) return false;
    return to <= from;
  }

  int _finished(BulkMigrationRunner r) => r.entries
      .where((e) =>
          e.phase != BulkEntryPhase.queued &&
          e.phase != BulkEntryPhase.searching)
      .length;

  bool _complete(BulkMigrationRunner r) => r.entries.every((e) =>
      e.phase != BulkEntryPhase.queued && e.phase != BulkEntryPhase.searching);

  /// Manual target search for one row — pops back the chosen target and sets it
  /// on the runner (Komikku parity), instead of launching a separate migration.
  Future<void> _searchManually(BuildContext context, BulkMigrationRunner r,
      int fromMangaId, MangaDto? source) async {
    if (source == null) return;
    final picked = await MigrationGlobalSearchRoute(
      $extra: MigrationRouteData(sourceManga: source),
    ).push<Object?>(context);
    if (picked is MangaDto) {
      r.overrideTarget(fromMangaId, picked.id, picked.title);
    }
  }

  void _openSettings(
    BuildContext context,
    BulkMigrationRunner r,
    ValueNotifier<bool> hideUnmatched,
    ValueNotifier<bool> hideWithoutUpdates,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MigrationConfigSheet(
        isSingleEntry: r.entries.length == 1,
        onStart: (config, _) {
          Navigator.of(context).pop();
          hideUnmatched.value = config.hideUnmatched;
          hideWithoutUpdates.value = config.hideWithoutUpdates;
          r.options = r.options.copyWith(
            migrateChapters: config.migrateChapters,
            migrateCategories: config.migrateCategories,
            migrateTracking: config.migrateTracking,
            migrateReaderSettings: config.migrateReaderSettings,
            migrateOfflineSettings: config.migrateOfflineSettings,
            migrateDownloads: config.migrateDownloads,
          );
        },
      ),
    );
  }

  Future<void> _confirm(BuildContext context, BulkMigrationRunner r,
      {required bool deleteSource}) async {
    final l10n = context.l10n;
    final committing = {
      for (final e in r.entries)
        if (e.phase == BulkEntryPhase.ready && e.toMangaId != null)
          e.fromMangaId,
    };
    if (committing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleteSource
            ? l10n.migrateSeriesCount(committing.length)
            : l10n.copySeriesCount(committing.length)),
        content: Text(deleteSource
            ? l10n.migrationActionMigrateDescription
            : l10n.migrationActionCopyDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    // Blocking progress while copying/removing (Komikku MigrationProgressDialog).
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MigrationProgressDialog(
        runner: r,
        committing: committing,
        onCancel: r.cancel,
      ),
    ));
    await r.commit(deleteSource: deleteSource);
    if (context.mounted) Navigator.of(context).pop(); // dismiss progress dialog
    if (r.isCancelled) return; // cancelled: stay on the list (Komikku parity)

    final migrated =
        committing.where((id) => _committed(r, id)).length;
    messenger.showSnackBar(SnackBar(
      content: Text(deleteSource
          ? l10n.migrationDoneMigrated(migrated)
          : l10n.migrationDoneCopied(migrated)),
    ));
    if (context.mounted) context.pop(); // back to the library
  }

  /// Per-row Migrate/Copy: commit the one entry, drop it, and pop to the library
  /// once the list empties (Komikku `migrateNow` → `removeManga`).
  Future<void> _commitRow(BuildContext context, BulkMigrationRunner r,
      int fromMangaId, {required bool deleteSource}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await r.commitOne(fromMangaId, deleteSource: deleteSource);
    final ok = _committed(r, fromMangaId);
    r.remove(fromMangaId);
    if (ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(deleteSource
            ? l10n.migrationDoneMigrated(1)
            : l10n.migrationDoneCopied(1)),
      ));
    }
    if (r.entries.isEmpty && context.mounted) context.pop();
  }

  /// Whether the entry reached [BulkEntryPhase.done] (or was already gone).
  bool _committed(BulkMigrationRunner r, int fromMangaId) {
    for (final e in r.entries) {
      if (e.fromMangaId == fromMangaId) return e.phase == BulkEntryPhase.done;
    }
    return true;
  }
}

Future<double?> _latestChapter(MangaBookRepository repo, int mangaId) async =>
    _latestOf(await repo.getChapterList(mangaId));

double? _latestOf(List<dynamic>? chapters) {
  if (chapters == null || chapters.isEmpty) return null;
  double? best;
  for (final c in chapters) {
    final n = (c.chapterNumber as num).toDouble();
    if (n >= 0 && (best == null || n > best)) best = n;
  }
  return best;
}

/// One source → target comparison row (Komikku layout).
class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.runner,
    required this.onSearchManually,
    required this.onCommitRow,
  });

  final BulkMigrationEntry entry;
  final BulkMigrationRunner runner;
  final VoidCallback onSearchManually;
  final void Function(bool deleteSource) onCommitRow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _MangaCard(
                title: entry.fromTitle,
                thumbnailUrl: entry.fromThumbnailUrl,
                source: entry.fromSourceName,
                chapterCount: entry.fromChapterCount,
                latestChapter: entry.fromLatestChapter,
              ),
            ),
            const Expanded(flex: 1, child: Icon(Icons.arrow_forward)),
            Expanded(flex: 5, child: _ResultCard(entry: entry)),
            SizedBox(
              width: 40,
              child: _ActionMenu(
                entry: entry,
                runner: runner,
                onSearchManually: onSearchManually,
                onCommitRow: onCommitRow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.entry});
  final BulkMigrationEntry entry;

  @override
  Widget build(BuildContext context) {
    switch (entry.phase) {
      case BulkEntryPhase.queued:
      case BulkEntryPhase.searching:
        return const AspectRatio(
          aspectRatio: 0.7,
          child: Center(child: CircularProgressIndicator()),
        );
      case BulkEntryPhase.noMatch:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.surfaceContainerHighest,
                  borderRadius: KBorderRadius.r8.radius,
                ),
                child: Icon(Icons.broken_image_outlined,
                    color: context.theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(context.l10n.migrationListNoMatch,
                  style: context.theme.textTheme.titleSmall),
            ),
          ],
        );
      default:
        if (entry.toMangaId == null) return const SizedBox.shrink();
        return _MangaCard(
          title: entry.toTitle ?? '',
          thumbnailUrl: entry.toThumbnailUrl,
          source: entry.toSourceName,
          chapterCount: entry.toChapterCount,
          latestChapter: entry.toLatestChapter,
        );
    }
  }
}

class _MangaCard extends StatelessWidget {
  const _MangaCard({
    required this.title,
    required this.thumbnailUrl,
    required this.source,
    required this.chapterCount,
    required this.latestChapter,
  });

  final String title;
  final String? thumbnailUrl;
  final String? source;
  final int chapterCount;
  final double? latestChapter;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: KBorderRadius.r8.radius,
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 0.7,
                child: SizedBox.expand(
                  child: ServerImage(
                    imageUrl: thumbnailUrl ?? '',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              if (chapterCount > 0)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('$chapterCount',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onPrimary)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(source ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall),
        Text(
          context.l10n.migrationLatestChapter(
              latestChapter == null ? '?' : _fmt(latestChapter!)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.entry,
    required this.runner,
    required this.onSearchManually,
    required this.onCommitRow,
  });

  final BulkMigrationEntry entry;
  final BulkMigrationRunner runner;
  final VoidCallback onSearchManually;
  final void Function(bool deleteSource) onCommitRow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (entry.phase == BulkEntryPhase.searching ||
        entry.phase == BulkEntryPhase.queued) {
      return IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => runner.skip(entry.fromMangaId),
      );
    }
    if (entry.phase == BulkEntryPhase.copying ||
        entry.phase == BulkEntryPhase.removing ||
        entry.phase == BulkEntryPhase.done) {
      return const SizedBox.shrink();
    }
    final hasMatch = entry.toMangaId != null;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'search':
            onSearchManually();
          case 'skip':
            runner.skip(entry.fromMangaId);
          case 'migrate':
            onCommitRow(true);
          case 'copy':
            onCommitRow(false);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
            value: 'search', child: Text(l10n.migrationSearchManually)),
        PopupMenuItem(value: 'skip', child: Text(l10n.migrationSkip)),
        if (hasMatch) ...[
          PopupMenuItem(
              value: 'migrate', child: Text(l10n.migrationMigrateNow)),
          PopupMenuItem(value: 'copy', child: Text(l10n.migrationCopyNow)),
        ],
      ],
    );
  }
}

/// Non-dismissible progress while a batch commits (Komikku `MigrationProgressDialog`).
/// Progress = committed entries over the set that was confirmed for this run.
class _MigrationProgressDialog extends StatelessWidget {
  const _MigrationProgressDialog({
    required this.runner,
    required this.committing,
    required this.onCancel,
  });

  final BulkMigrationRunner runner;
  final Set<int> committing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: AnimatedBuilder(
        animation: runner,
        builder: (context, _) {
          final done = runner.entries
              .where((e) =>
                  committing.contains(e.fromMangaId) &&
                  (e.phase == BulkEntryPhase.done ||
                      e.phase == BulkEntryPhase.failed ||
                      e.phase == BulkEntryPhase.dirtyBlocked))
              .length;
          final value = committing.isEmpty ? null : done / committing.length;
          return LinearProgressIndicator(value: value);
        },
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
