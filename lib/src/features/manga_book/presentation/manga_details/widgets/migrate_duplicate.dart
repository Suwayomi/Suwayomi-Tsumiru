// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../../migration/controller/bulk_migration_providers.dart';
import '../../../../migration/data/bulk_migration_runner.dart';
import '../../../../migration/domain/bulk_migration_types.dart';
import '../../../../migration/domain/migration_models.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../domain/manga/manga_model.dart';

/// Migrates an existing library entry [from] into the manga being added [to],
/// driven entirely by the shipped bulk-migration runner so its dirty-state
/// gate, crash journal, auth-pause, and device-local carry all apply — the raw
/// copy/remove sequence would skip every one of those safeties.
///
/// Manual-target path (Komikku's dialog-migrate): [overrideTarget] pins the
/// candidate as the target, so no source search runs. Tracking carries by
/// design (recorded decision); every other flag stays at its shipped default
/// (chapters/categories/reader/offline on, downloads off, deleteSource true).
/// Returns true when the migrate completed.
Future<bool> migrateDuplicateIntoCandidate(
  WidgetRef ref,
  BuildContext context, {
  required MangaDto from,
  required MangaDto to,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final runner = buildBulkMigrationRunner(
    container: container,
    entries: [
      BulkMigrationEntry(
        fromMangaId: from.id,
        fromTitle: from.title,
        fromThumbnailUrl: from.thumbnailUrl,
        fromSourceName: from.source?.displayName,
        fromChapterCount: from.chapters.totalCount,
      ),
    ],
    targetSourceIds: [to.sourceId],
    options: const MigrationOption(migrateTracking: true),
    // Route through the container so the device reconcile still lands if this
    // dialog's widget is disposed before the migrate finishes.
    onSourceRemoved: (id) => reconcileMangaContainer(container, id),
  );
  runner.overrideTarget(from.id, to.id, to.title);

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SingleMigrationProgressDialog(
      runner: runner,
      fromMangaId: from.id,
      onCancel: runner.cancel,
    ),
  ));

  // commitOne can throw CancelledException where the batch commit() swallows
  // it; the finally keeps the non-dismissible progress dialog from stranding.
  var done = false;
  try {
    await runner.commitOne(from.id, deleteSource: true);
    done = _isDone(runner, from.id);
  } finally {
    if (context.mounted) {
      Navigator.of(context).pop(); // dismiss the progress dialog
      // A migrate adds the candidate to the library and removes the source, so
      // the list must refetch; skip it if we're gone (the ref would be disposed).
      if (done) ref.invalidate(libraryMangaListProvider);
    }
  }
  return done;
}

bool _isDone(BulkMigrationRunner runner, int fromMangaId) {
  for (final e in runner.entries) {
    if (e.fromMangaId == fromMangaId) return e.phase == BulkEntryPhase.done;
  }
  return false;
}

/// Non-dismissible progress while the one migrate copies/removes — the
/// single-entry analogue of the bulk run screen's MigrationProgressDialog.
class _SingleMigrationProgressDialog extends StatelessWidget {
  const _SingleMigrationProgressDialog({
    required this.runner,
    required this.fromMangaId,
    required this.onCancel,
  });

  final BulkMigrationRunner runner;
  final int fromMangaId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: AnimatedBuilder(
        animation: runner,
        builder: (context, _) {
          final settled = _isSettled(runner, fromMangaId);
          return LinearProgressIndicator(value: settled ? 1 : null);
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

  static bool _isSettled(BulkMigrationRunner runner, int fromMangaId) {
    for (final e in runner.entries) {
      if (e.fromMangaId != fromMangaId) continue;
      return e.phase == BulkEntryPhase.done ||
          e.phase == BulkEntryPhase.failed ||
          e.phase == BulkEntryPhase.dirtyBlocked;
    }
    return true;
  }
}
