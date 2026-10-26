// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../utils/theme/brand.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/desktop/desktop_window.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../browse_center/domain/source/source_model.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_server_identity_repository.dart';
import '../../controller/bulk_migration_providers.dart';
import '../../data/bulk_migration_runner.dart';
import '../../domain/bulk_migration_types.dart';
import '../../domain/chapter_matcher.dart';
import '../../domain/migration_models.dart';
import '../migration_block_reason_text.dart';
import '../widgets/migration_config_sheet.dart';
import 'migration_global_search_screen.dart';

class MigrationBulkRunScreen extends StatelessWidget {
  const MigrationBulkRunScreen({super.key, required this.data});

  final MigrationBulkRunData data;

  @override
  Widget build(BuildContext context) => MigrationBulkRunBody(data: data);
}

class MigrationBulkRunBody extends HookConsumerWidget {
  const MigrationBulkRunBody({
    super.key,
    required this.data,
    this.onBack,
    this.onFinished,
    this.windowed = false,
  });

  final MigrationBulkRunData data;
  final VoidCallback? onBack;
  final VoidCallback? onFinished;

  final bool windowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final library = ref.watch(libraryMangaListProvider);
    final sources = ref.watch(searchableSourcesProvider);
    final runner = useState<BulkMigrationRunner?>(null);
    final unavailable = useState(false);
    final startupError = useState<String?>(null);
    final retry = useState(0);
    final authState = ref.watch(authCredentialsStoreProvider);
    final authType = ref.watch(authTypeKeyProvider);
    final serverIdentity = authType == AuthType.uiLogin
        ? null
        : ref.watch(serverInstanceIdProvider);
    final identityUnavailable =
        serverIdentity?.hasError == true ||
        (serverIdentity?.asData?.value.isEmpty ?? false);
    final identityReady =
        serverIdentity == null ||
        (!serverIdentity.isLoading &&
            !serverIdentity.hasError &&
            (serverIdentity.asData?.value.isNotEmpty ?? false));
    final origin = useMemoized(() {
      final store = ref.read(authCredentialsStoreProvider.notifier);
      return (store: store, epoch: store.sessionEpoch);
    }, const []);
    final sameSession =
        !origin.store.sessionChanging &&
        origin.store.sessionEpoch == origin.epoch;
    final hideUnmatched = useState(data.hideUnmatched);
    final hideWithoutUpdates = useState(data.hideWithoutUpdates);

    final sourceById = {for (final m in library.value ?? const []) m.id: m};
    // Resolve outside useEffect; hook initialization cannot look up inherited widgets.
    final container = ProviderScope.containerOf(context, listen: false);

    useEffect(() {
      return () {
        runner.value?.cancel();
      };
    }, const []);

    final startupKeys = [
      library,
      sources,
      retry.value,
      sameSession,
      authState.value?.sessionEpoch,
      identityReady,
      identityUnavailable,
    ];
    useEffect(() {
      if (!sameSession) {
        runner.value?.cancel();
        unavailable.value = true;
        return null;
      }
      if (runner.value != null) return null;
      if (identityUnavailable) {
        unavailable.value = true;
        return null;
      }
      if (!identityReady) {
        unavailable.value = false;
        return null;
      }
      final mangas = library.value;
      if (mangas == null) return null;
      if (sources.isLoading) return null;
      final byId = {for (final m in mangas) m.id: m};
      final entries = [
        for (final id in data.mangaIds)
          if (byId[id] != null)
            BulkMigrationEntry(
              fromMangaId: id,
              fromTitle: byId[id]!.title,
              fromSourceId: byId[id]!.sourceId,
              fromThumbnailUrl: byId[id]!.thumbnailUrl,
              fromSourceName: byId[id]!.source?.displayName,
              fromChapterCount: byId[id]!.chapters.totalCount,
            ),
      ];
      BulkMigrationRunner r;
      try {
        r = buildBulkMigrationRunner(
          container: container,
          entries: entries,
          targetSourceIds: data.targetSourceIds,
          options: data.options,
          sources: sources.value ?? const [],
          extraSearchQuery: data.extraSearchQuery,
          onSourceRemoved: (id) => reconcileMangaContainer(container, id),
        );
      } catch (_) {
        unavailable.value = true;
        return null;
      }
      unavailable.value = false;
      startupError.value = null;
      runner.value = r;
      Future<void>(() async {
        try {
          if (r.isCancelled) return;
          final repo = ref.read(mangaBookRepositoryProvider);
          for (final e in entries) {
            if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
            final latest = await _latestChapter(repo, e.fromMangaId);
            if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
            e.fromLatestChapter = latest;
          }
          if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
          r.notify();
          await r.search();
          await r.preflight();
          for (final e in r.entries) {
            if (e.toMangaId == null) continue;
            if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
            await r.inspectTarget(e.fromMangaId);
          }
          if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
          r.notify();
        } catch (error) {
          if (!r.isCancelled) {
            startupError.value = '$error';
          }
        }
      });
      return null;
    }, startupKeys);

    final r = sameSession && !unavailable.value && startupError.value == null
        ? runner.value
        : null;
    final topBar = showsMergedTopBar(context);
    final title = Text(
      r == null || r.entries.isEmpty
          ? l10n.migrationListTitle
          : l10n.migrationListTitleProgress(_finished(r), r.entries.length),
    );
    final List<Widget>? actions = r == null
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
                      icon: const Icon(FluentIcons.settings_24_regular),
                      onPressed: () => _openSettings(
                        context,
                        r,
                        hideUnmatched,
                        hideWithoutUpdates,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.migrationActionCopy,
                      icon: Icon(
                        single
                            ? FluentIcons.copy_24_regular
                            : FluentIcons.copy_select_24_regular,
                      ),
                      onPressed: complete && _copyableCount(r) > 0
                          ? () => _confirm(context, r, deleteSource: false)
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.migrationActionMigrate,
                      icon: Icon(
                        single ? FluentIcons.checkmark_24_regular : FluentIcons.checkmark_starburst_24_regular,
                      ),
                      onPressed: complete && _migratableCount(r) > 0
                          ? () => _confirm(context, r, deleteSource: true)
                          : null,
                    ),
                  ],
                );
              },
            ),
          ];
    final content = unavailable.value || !sameSession
          ? Emoticons(
              title: l10n.migrationIdentityUnavailable,
              button: TextButton(
                onPressed: () async {
                  ref.invalidate(serverInstanceIdProvider);
                  try {
                    await container.read(serverInstanceIdProvider.future);
                  } catch (_) {}
                  if (!context.mounted) return;
                  ref.invalidate(libraryMangaListProvider);
                  retry.value++;
                },
                child: Text(l10n.retry),
              ),
            )
          : startupError.value != null
          ? Emoticons(
              title: startupError.value,
              button: TextButton(
                onPressed: () {
                  runner.value?.cancel();
                  runner.value = null;
                  startupError.value = null;
                  retry.value++;
                },
                child: Text(l10n.retry),
              ),
            )
          : r == null
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
                final list = ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _Row(
                    entry: visible[i],
                    desktop: windowed,
                    runner: r,
                    onSearchManually: () => _searchManually(
                      context,
                      r,
                      visible[i].fromMangaId,
                      sourceById[visible[i].fromMangaId],
                    ),
                    onCommitRow: (deleteSource) => _commitRow(
                      context,
                      r,
                      visible[i].fromMangaId,
                      deleteSource: deleteSource,
                    ),
                    onRetry: (id) => _retryRow(context, r, id),
                  ),
                );
                if (windowed ||
                    context.windowSizeClass < WindowSizeClass.large) {
                  return list;
                }
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: kShortSearchCoverWidth * 11 / 5 + 40 + 24,
                    child: list,
                  ),
                );
              },
            );
    if (windowed) {
      return Column(
        children: [
          if (r != null)
            AnimatedBuilder(
              animation: r,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.migrationListTitleProgress(
                        _finished(r),
                        r.entries.length,
                      ),
                    ),
                    if (!_complete(r)) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: r.entries.isEmpty
                            ? null
                            : _finished(r) / r.entries.length,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Expanded(child: content),
          const Divider(height: 1),
          if (r == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onBack, child: Text(l10n.back)),
              ),
            )
          else
            _CommitFooter(
              runner: r,
              onBack: onBack,
              onCommit: (deleteSource) =>
                  _confirm(context, r, deleteSource: deleteSource),
            ),
        ],
      );
    }
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              actions: actions,
            ),
      body: content,
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1),
                  _CommitFooter(
                    runner: r,
                    compact: true,
                    onCommit: (deleteSource) =>
                        _confirm(context, r, deleteSource: deleteSource),
                  ),
                ],
              ),
            ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      actions: actions ?? const [],
      child: scaffold,
    );
  }

  bool _noUpdates(BulkMigrationEntry e) {
    if (e.toMangaId == null) return false;
    final from = e.fromLatestChapter;
    final to = e.toLatestChapter;
    if (from == null || to == null) return false;
    return to <= from;
  }

  Future<void> _searchManually(
    BuildContext context,
    BulkMigrationRunner r,
    int fromMangaId,
    MangaDto? source,
  ) async {
    if (source == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final picked = windowed
        ? await showGeneralDialog<MangaDto>(
            context: context,
            barrierColor: Colors.transparent,
            pageBuilder: (context, _, _) => DesktopWindow(
              onClose: () => Navigator.of(context).pop(),
              child: MigrationGlobalSearchScreen(
                sourceManga: source,
                onSelected: (manga) => Navigator.of(context).pop(manga),
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          )
        : await MigrationGlobalSearchRoute(
            $extra: MigrationRouteData(sourceManga: source),
          ).push<Object?>(context);
    if (picked is MangaDto) {
      final sourceNames = {
        for (final s
            in container.read(searchableSourcesProvider).value ?? const <SourceDto>[])
          s.id: s.displayName,
      };
      final cover = picked.displayCoverUrl;
      r.overrideTarget(
        fromMangaId,
        picked.id,
        picked.title,
        toThumbnailUrl: cover.isEmpty ? picked.thumbnailUrl : cover,
        toSourceName:
            picked.source?.displayName ?? sourceNames[picked.sourceId],
        toSourceId: picked.sourceId,
      );
      if (r.isSessionCurrent?.call() == false || r.isCancelled) return;
      await r.inspectTarget(fromMangaId);
      r.notify();
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
      sheetAnimationStyle: context.motionStyle,
    );
  }

  Future<void> _confirm(
    BuildContext context,
    BulkMigrationRunner r, {
    required bool deleteSource,
  }) async {
    final l10n = context.l10n;
    final committing = {
      for (final e in r.entries)
        if (deleteSource ? r.isMigratable(e) : r.isCopyable(e))
          e.fromMangaId,
    };
    if (committing.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          deleteSource
              ? l10n.migrateSeriesCount(committing.length)
              : l10n.copySeriesCount(committing.length),
        ),
        content: Text(
          deleteSource
              ? l10n.migrationActionMigrateDescription
              : l10n.migrationActionCopyDescription,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              deleteSource
                  ? l10n.migrationActionMigrate
                  : l10n.migrationActionCopy,
            ),
          ),
        ],
      ),
      animationStyle: context.motionStyle,
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final snackBarMotionStyle = context.snackBarMotionStyle;
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MigrationProgressDialog(
          runner: r,
          committing: committing,
          onCancel: r.cancel,
        ),
        animationStyle: context.motionStyle,
      ).then((_) {
        dialogOpen = false;
      }),
    );
    await r.commit(deleteSource: deleteSource);
    if (dialogOpen && context.mounted) {
      Navigator.of(context).pop(); // dismiss progress dialog
    }
    if (r.isCancelled) return; // cancelled: stay on the list (Komikku parity)

    final failed = committing.where((id) => _stillFailed(r, id)).length;
    if (failed > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.migrationFailedSnack(failed))),
        snackBarAnimationStyle: snackBarMotionStyle,
      );
    } else {
      final migrated = committing.where((id) => _committed(r, id)).length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            deleteSource
                ? l10n.migrationDoneMigrated(migrated)
                : l10n.migrationDoneCopied(migrated),
          ),
        ),
        snackBarAnimationStyle: snackBarMotionStyle,
      );
    }
    if (context.mounted) _finish(context);
  }

  Future<void> _commitRow(
    BuildContext context,
    BulkMigrationRunner r,
    int fromMangaId, {
    required bool deleteSource,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final snackBarMotionStyle = context.snackBarMotionStyle;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          deleteSource
              ? l10n.migrateSeriesCount(1)
              : l10n.copySeriesCount(1),
        ),
        content: Text(
          deleteSource
              ? l10n.migrationActionMigrateDescription
              : l10n.migrationActionCopyDescription,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              deleteSource
                  ? l10n.migrationActionMigrate
                  : l10n.migrationActionCopy,
            ),
          ),
        ],
      ),
      animationStyle: context.motionStyle,
    );
    if (confirmed != true || !context.mounted) return;
    await r.commitOne(fromMangaId, deleteSource: deleteSource);
    if (r.isCancelled) return;
    final ok = _committed(r, fromMangaId);
    if (ok) {
      r.remove(fromMangaId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            deleteSource
                ? l10n.migrationDoneMigrated(1)
                : l10n.migrationDoneCopied(1),
          ),
        ),
        snackBarAnimationStyle: snackBarMotionStyle,
      );
    } else if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.migrationFailedSnack(1))),
        snackBarAnimationStyle: snackBarMotionStyle,
      );
    }
    if (r.entries.isEmpty && context.mounted) _finish(context);
  }

  Future<void> _retryRow(
    BuildContext context,
    BulkMigrationRunner r,
    int fromMangaId,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final snackBarMotionStyle = context.snackBarMotionStyle;
    await r.retryOne(fromMangaId);
    if (!context.mounted || r.isCancelled) return;
    if (_stillFailed(r, fromMangaId)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.migrationFailedSnack(1))),
        snackBarAnimationStyle: snackBarMotionStyle,
      );
    }
  }

  void _finish(BuildContext context) {
    if (onFinished != null) {
      onFinished!();
    } else {
      context.pop();
    }
  }

  bool _committed(BulkMigrationRunner r, int fromMangaId) {
    for (final e in r.entries) {
      if (e.fromMangaId == fromMangaId) return e.phase == BulkEntryPhase.done;
    }
    return true;
  }
}

Future<double?> _latestChapter(MangaBookRepository repo, int mangaId) async {
  try {
    return latestChapterNumber(
      (await repo.getStoredChapterList(mangaId))?.map((c) => c.chapterNumber),
    );
  } catch (_) {
    return null;
  }
}

int _finished(BulkMigrationRunner r) => r.entries
    .where(
      (e) =>
          e.phase != BulkEntryPhase.queued &&
          e.phase != BulkEntryPhase.searching,
    )
    .length;

bool _complete(BulkMigrationRunner r) => r.entries.every(
  (e) => e.phase != BulkEntryPhase.queued && e.phase != BulkEntryPhase.searching,
);

int _copyableCount(BulkMigrationRunner r) =>
    r.entries.where(r.isCopyable).length;

int _migratableCount(BulkMigrationRunner r) =>
    r.entries.where(r.isMigratable).length;

int _failedCount(BulkMigrationRunner r) => r.entries
    .where(_isFailed)
    .length;

bool _isFailed(BulkMigrationEntry e) =>
    e.phase == BulkEntryPhase.failed ||
    e.phase == BulkEntryPhase.dirtyBlocked;

bool _stillFailed(BulkMigrationRunner r, int fromMangaId) {
  for (final e in r.entries) {
    if (e.fromMangaId == fromMangaId) return _isFailed(e);
  }
  return false;
}

// Blocked reasons render once beside the target; this line covers other failures.
String? _failureMessage(BuildContext context, BulkMigrationEntry e) {
  final failure = migrationFailureText(context.l10n, e);
  if (failure != null) return failure;
  final message = e.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  if (e.blockKind != null || !_isFailed(e)) return null;
  return context.l10n.migrationFailedGeneric;
}

String? _failureDetail(BulkMigrationEntry e) {
  final detail = e.failureDetail?.trim();
  return detail != null && detail.isNotEmpty ? detail : null;
}

String? _blockedReason(BuildContext context, BulkMigrationEntry e) =>
    migrationBlockReasonText(context.l10n, e);

String _targetSubtitle(BuildContext context, BulkMigrationEntry e) {
  final blocked = _blockedReason(context, e);
  if (blocked != null) return blocked;
  final l10n = context.l10n;
  final source = e.toSourceName ?? l10n.unknownSource;
  final latest = l10n.migrationLatestChapter(
    e.toLatestChapter?.toString() ?? '?',
  );
  return '$source · $latest';
}

class _CommitFooter extends StatelessWidget {
  const _CommitFooter({
    required this.runner,
    required this.onCommit,
    this.onBack,
    this.compact = false,
  });

  final BulkMigrationRunner runner;
  final void Function(bool deleteSource) onCommit;
  final VoidCallback? onBack;

  /// Short labels so the bar fits narrow phones alongside the failed count.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: runner,
      builder: (context, _) {
        final failed = _failedCount(runner);
        final migrateCount = _migratableCount(runner);
        final canCopy =
            _complete(runner) && _copyableCount(runner) > 0;
        final canCommit = _complete(runner) && migrateCount > 0;
        final migrate = compact
            ? TextButton(
                onPressed: canCommit ? () => onCommit(true) : null,
                child: Text(l10n.migrationActionMigrate),
              )
            : FilledButton(
                onPressed: canCommit ? () => onCommit(true) : null,
                child: Text(l10n.migrateSeriesCount(migrateCount)),
              );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (failed > 0)
                Flexible(
                  child: Text(
                    l10n.migrationFailedCount(failed),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.theme.colorScheme.error,
                    ),
                  ),
                ),
              const Spacer(),
              if (onBack != null) ...[
                TextButton(onPressed: onBack, child: Text(l10n.back)),
                const SizedBox(width: 8),
              ],
              TextButton(
                onPressed: canCopy ? () => onCommit(false) : null,
                child: Text(l10n.migrationActionCopy),
              ),
              const SizedBox(width: 8),
              migrate,
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.runner,
    required this.onSearchManually,
    required this.onCommitRow,
    required this.onRetry,
    this.desktop = false,
  });

  final bool desktop;
  final BulkMigrationEntry entry;
  final BulkMigrationRunner runner;
  final VoidCallback onSearchManually;
  final void Function(bool deleteSource) onCommitRow;
  final void Function(int fromMangaId) onRetry;

  @override
  Widget build(BuildContext context) {
    if (desktop) {
      final l10n = context.l10n;
      final failure = _failureMessage(context, entry);
      final searching =
          entry.phase == BulkEntryPhase.queued ||
          entry.phase == BulkEntryPhase.searching;
      final busy =
          entry.phase == BulkEntryPhase.copying ||
          entry.phase == BulkEntryPhase.removing ||
          entry.phase == BulkEntryPhase.done ||
          runner.isBusy(entry.fromMangaId);
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: _ReviewSeries(
                  title: entry.fromTitle,
                  thumbnailUrl: entry.fromThumbnailUrl,
                  subtitle: entry.fromSourceName ?? '',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(FluentIcons.arrow_right_24_regular, size: 20),
              ),
              Expanded(
                child: searching
                    ? const Center(child: CircularProgressIndicator())
                    : entry.toMangaId == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.migrationListNoMatch),
                          if (_isFailed(entry) && failure != null) ...[
                            const SizedBox(height: 4),
                            _FailureReason(
                              message: failure,
                              detail: _failureDetail(entry),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ReviewSeries(
                            title: entry.toTitle ?? '',
                            thumbnailUrl: entry.toThumbnailUrl,
                            subtitle: _targetSubtitle(context, entry),
                            subtitleColor: entry.blocksMigrate
                                ? context.theme.colorScheme.error
                                : null,
                          ),
                          if (entry.phase == BulkEntryPhase.needsReview) ...[
                            const SizedBox(height: 4),
                            const _NeedsReviewLabel(),
                          ],
                          if (_isFailed(entry) && failure != null) ...[
                            const SizedBox(height: 4),
                            _FailureReason(
                              message: failure,
                              detail: _failureDetail(entry),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              if (!busy) ...[
                if (_isFailed(entry))
                  TextButton(
                    onPressed: () => onRetry(entry.fromMangaId),
                    child: Text(l10n.retry),
                  ),
                if (!searching)
                  TextButton(
                    onPressed: onSearchManually,
                    child: Text(l10n.migrationSearchManually),
                  ),
                TextButton(
                  onPressed: () => runner.skip(entry.fromMangaId),
                  child: Text(l10n.migrationSkip),
                ),
                if (!searching && entry.toMangaId != null) ...[
                  if (!entry.blocksMigrate)
                    TextButton(
                      onPressed: () => onCommitRow(true),
                      child: Text(l10n.migrationMigrateNow),
                    ),
                  TextButton(
                    onPressed: () => onCommitRow(false),
                    child: Text(l10n.migrationCopyNow),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    }
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
            const Expanded(flex: 1, child: Icon(FluentIcons.arrow_right_24_regular)),
            Expanded(flex: 5, child: _ResultCard(entry: entry)),
            SizedBox(
              width: 40,
              child: _ActionMenu(
                entry: entry,
                runner: runner,
                onSearchManually: onSearchManually,
                onCommitRow: onCommitRow,
                onRetry: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedsReviewLabel extends StatelessWidget {
  const _NeedsReviewLabel();

  @override
  Widget build(BuildContext context) => Text(
    context.l10n.migrationNeedsReview,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: context.textTheme.bodySmall?.copyWith(
      color: context.theme.colorScheme.tertiary,
    ),
  );
}

class _FailureReason extends StatelessWidget {
  const _FailureReason({required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: detail ?? message,
    child: Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.theme.colorScheme.error,
      ),
    ),
  );
}

class _ReviewSeries extends StatelessWidget {
  const _ReviewSeries({
    required this.title,
    required this.thumbnailUrl,
    required this.subtitle,
    this.subtitleColor,
  });

  final String title;
  final String? thumbnailUrl;
  final String subtitle;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: KBorderRadius.r8.radius,
        child: ServerImage(
          imageUrl: thumbnailUrl ?? '',
          size: const Size(48, 68),
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: subtitleColor,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.entry});
  final BulkMigrationEntry entry;

  @override
  Widget build(BuildContext context) {
    final failure = _failureMessage(context, entry);
    switch (entry.phase) {
      case BulkEntryPhase.queued:
      case BulkEntryPhase.searching:
        return const AspectRatio(
          aspectRatio: kMangaCoverAspectRatio,
          child: Center(child: CircularProgressIndicator()),
        );
      case BulkEntryPhase.noMatch:
      case BulkEntryPhase.failed when entry.toMangaId == null:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: kMangaCoverAspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.surfaceContainerHighest,
                  borderRadius: KBorderRadius.r8.radius,
                ),
                child: Icon(
                  FluentIcons.image_off_24_regular,
                  color: context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                context.l10n.migrationListNoMatch,
                style: context.theme.textTheme.titleSmall,
              ),
            ),
            if (_isFailed(entry) && failure != null)
              _FailureReason(message: failure),
          ],
        );
      default:
        if (entry.toMangaId == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MangaCard(
              title: entry.toTitle ?? '',
              thumbnailUrl: entry.toThumbnailUrl,
              source: entry.toSourceName ?? context.l10n.unknownSource,
              chapterCount: entry.toChapterCount,
              latestChapter: entry.toLatestChapter,
              blockedMessage: _blockedReason(context, entry),
            ),
            if (entry.phase == BulkEntryPhase.needsReview)
              const _NeedsReviewLabel(),
            if (_isFailed(entry) && failure != null) ...[
              const SizedBox(height: 4),
              _FailureReason(message: failure),
            ],
          ],
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
    this.blockedMessage,
  });

  final String title;
  final String? thumbnailUrl;
  final String? source;
  final int chapterCount;
  final double? latestChapter;
  final String? blockedMessage;

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
                aspectRatio: kMangaCoverAspectRatio,
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
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: OnImage.text,
                    ),
                  ),
                ),
              ),
              if (chapterCount > 0)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$chapterCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          source ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        if (blockedMessage != null)
          Text(
            blockedMessage!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else
          Text(
            context.l10n.migrationLatestChapter(
              latestChapter == null ? '?' : _fmt(latestChapter!),
            ),
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
    required this.onRetry,
  });

  final BulkMigrationEntry entry;
  final BulkMigrationRunner runner;
  final VoidCallback onSearchManually;
  final void Function(bool deleteSource) onCommitRow;
  final void Function(int fromMangaId) onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (entry.phase == BulkEntryPhase.searching ||
        entry.phase == BulkEntryPhase.queued) {
      return IconButton(
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: () => runner.skip(entry.fromMangaId),
      );
    }
    if (runner.isBusy(entry.fromMangaId) ||
        entry.phase == BulkEntryPhase.copying ||
        entry.phase == BulkEntryPhase.removing ||
        entry.phase == BulkEntryPhase.done) {
      return const SizedBox.shrink();
    }
    final hasMatch = entry.toMangaId != null;
    final canRetry = _isFailed(entry);
    return PopupMenuButton<String>(
      icon: const Icon(FluentIcons.more_vertical_24_regular),
      onSelected: (value) {
        switch (value) {
          case 'search':
            onSearchManually();
          case 'skip':
            runner.skip(entry.fromMangaId);
          case 'retry':
            onRetry(entry.fromMangaId);
          case 'migrate':
            onCommitRow(true);
          case 'copy':
            onCommitRow(false);
        }
      },
      itemBuilder: (context) => [
        if (canRetry)
          PopupMenuItem(
            value: 'retry',
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_clockwise_24_regular,
              label: l10n.retry,
            ),
          ),
        PopupMenuItem(
          value: 'search',
          child: ChapterMenuRow(
            icon: FluentIcons.search_24_regular,
            label: l10n.migrationSearchManually,
          ),
        ),
        PopupMenuItem(
          value: 'skip',
          child: ChapterMenuRow(
            icon: FluentIcons.dismiss_24_regular,
            label: l10n.migrationSkip,
          ),
        ),
        if (hasMatch) ...[
          PopupMenuItem(
            value: 'migrate',
            enabled: !entry.blocksMigrate,
            child: ChapterMenuRow(
              icon: FluentIcons.arrow_swap_24_regular,
              label: l10n.migrationMigrateNow,
            ),
          ),
          PopupMenuItem(
            value: 'copy',
            child: ChapterMenuRow(
              icon: FluentIcons.copy_24_regular,
              label: l10n.migrationCopyNow,
            ),
          ),
        ],
      ],
      popUpAnimationStyle: context.motionStyle,
    );
  }
}

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
    return AnimatedBuilder(
      animation: runner,
      builder: (context, _) {
        final done = runner.entries
            .where(
              (e) =>
                  committing.contains(e.fromMangaId) &&
                  (e.phase == BulkEntryPhase.done ||
                      e.phase == BulkEntryPhase.failed ||
                      e.phase == BulkEntryPhase.dirtyBlocked),
            )
            .length;
        final value = committing.isEmpty ? null : done / committing.length;
        final finished = runner.isCancelled || done >= committing.length;
        return PopScope(
          canPop: finished,
          child: AlertDialog(
            content: LinearProgressIndicator(value: value),
            actions: [
              TextButton(
                onPressed: onCancel,
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
