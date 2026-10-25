// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../library/presentation/library/controller/library_manga_list.dart';
import '../../../../migration/controller/bulk_migration_providers.dart';
import '../../../../migration/data/bulk_migration_runner.dart';
import '../../../../migration/domain/bulk_migration_types.dart';
import '../../../../migration/domain/migration_models.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../domain/manga/manga_model.dart';

/// Uses the migration runner and pinned target to preserve safety gates; returns true on completion.
Future<bool> migrateDuplicateIntoCandidate(
  WidgetRef ref,
  BuildContext context, {
  required MangaDto from,
  required MangaDto to,
}) async {
  if (!await confirmAction(
        context,
        title: context.l10n.migrationActionMigrate,
        message: context.l10n.confirmDuplicateMigrationMessage(
          '${from.title} (${from.source?.displayName ?? from.sourceId})',
          '${to.title} (${to.source?.displayName ?? to.sourceId})',
        ),
        action: context.l10n.migrationActionMigrate,
      ) ||
      !context.mounted) {
    return false;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final runner = buildBulkMigrationRunner(
    container: container,
    entries: [
      BulkMigrationEntry(
        fromMangaId: from.id,
        fromTitle: from.title,
        fromThumbnailUrl: from.displayCoverUrl,
        fromSourceName: from.source?.displayName,
        fromChapterCount: from.chapters.totalCount,
      ),
    ],
    targetSourceIds: [to.sourceId],
    options: const MigrationOption(migrateTracking: true),
    // Use the container so reconciliation survives dialog disposal.
    onSourceRemoved: (id) => reconcileMangaContainer(container, id),
  );
  runner.overrideTarget(from.id, to.id, to.title);

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SingleMigrationProgressDialog(
        runner: runner,
        fromMangaId: from.id,
        onCancel: runner.cancel,
      ),
      animationStyle: context.motionStyle,
    ),
  );

  // commitOne can throw CancelledException; finally must close the non-dismissible dialog.
  var done = false;
  try {
    await runner.commitOne(from.id, deleteSource: true);
    done = _isDone(runner, from.id);
  } finally {
    if (context.mounted) {
      Navigator.of(context).pop(); // dismiss the progress dialog
      // Migration changes library membership, so invalidate the list on success.
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
