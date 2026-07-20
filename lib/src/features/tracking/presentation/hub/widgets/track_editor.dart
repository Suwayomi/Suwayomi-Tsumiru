// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../controller/manga_track_records_controller.dart';
import '../../../data/graphql/__generated__/query.graphql.dart';
import '../../../data/tracker_repository.dart';
import 'tracker_search.dart';

/// Edits a bound track record's status, score, chapters, and dates.
///
/// Signature is fixed — Task 8 fills the body.
class TrackEditor extends ConsumerWidget {
  const TrackEditor({
    super.key,
    required this.tracker,
    required this.trackRecord,
    required this.mangaId,
  });

  final Fragment$TrackerDto tracker;
  final Fragment$TrackRecordDto trackRecord;
  final int mangaId;

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Runs [mutation], shows a toast on error and invalidates on both paths
  /// (success: server truth; error: revert to server truth).
  Future<void> _doUpdate(
    WidgetRef ref,
    BuildContext context,
    Future<void> Function() mutation,
  ) async {
    final result = await AsyncValue.guard(mutation);
    // Both branches touch ref; bail if the sheet was dismissed mid-flight.
    if (!context.mounted) return;
    if (result.hasError) {
      result.showToastOnError(ref.read(toastProvider));
      // Revert: re-read from server.
      ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
      return;
    }
    ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
  }

  // ------------------------------------------------------------------
  // Epoch-ms helpers
  // ------------------------------------------------------------------

  /// Converts a LongString epoch-ms ("0" = unset) to a [DateTime], or null.
  static DateTime? _epochToDate(String epochMs) {
    if (epochMs == '0' || epochMs.isEmpty) return null;
    final ms = int.tryParse(epochMs);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Converts a local-midnight [DateTime] to an epoch-ms String.
  static String _dateToEpoch(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day)
          .millisecondsSinceEpoch
          .toString();

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(trackerRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------------------------------------
        // Header: icon + title (tappable → remoteUrl) + private badge + ⋮
        // ---------------------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Image.network(
                tracker.icon,
                width: 20,
                height: 20,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.sync_rounded, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => launchUrlInWeb(
                    context,
                    trackRecord.remoteUrl,
                    ref.read(toastProvider),
                  ),
                  child: Text(
                    trackRecord.title,
                    style: context.textTheme.bodyMedium?.copyWith(
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (trackRecord.private)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Chip(
                    label: Text(
                      context.l10n.trackPrivateBadge,
                      style: context.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              // ⋮ overflow menu
              PopupMenuButton<_MenuAction>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) =>
                    _handleMenuAction(context, ref, repo, action),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _MenuAction.changeEntry,
                    child: Text(context.l10n.trackChangeEntry),
                  ),
                  if (tracker.supportsPrivateTracking)
                    PopupMenuItem(
                      value: _MenuAction.togglePrivate,
                      child: Text(
                        trackRecord.private
                            ? context.l10n.trackMarkPublic
                            : context.l10n.trackMarkPrivate,
                      ),
                    ),
                  PopupMenuItem(
                    value: _MenuAction.remove,
                    child: Text(context.l10n.trackRemoveEntry),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ---------------------------------------------------------------
        // Status row
        // ---------------------------------------------------------------
        _EditorRow(
          label: context.l10n.trackStatus,
          child: DropdownButton<int>(
            value: tracker.statuses
                    .any((s) => s.value == trackRecord.status)
                ? trackRecord.status
                : null,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: tracker.statuses
                .map(
                  (s) => DropdownMenuItem(
                    value: s.value,
                    child: Text(s.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _doUpdate(ref, context, () => repo.update(
                    recordId: trackRecord.id,
                    status: value,
                  ));
            },
          ),
        ),

        // ---------------------------------------------------------------
        // Score row
        // ---------------------------------------------------------------
        _EditorRow(
          label: context.l10n.trackScore,
          child: DropdownButton<String>(
            value: tracker.scores.contains(trackRecord.displayScore)
                ? trackRecord.displayScore
                : null,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: tracker.scores
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _doUpdate(ref, context, () => repo.update(
                    recordId: trackRecord.id,
                    scoreString: value,
                  ));
            },
          ),
        ),

        // ---------------------------------------------------------------
        // Chapters read row — tap the value to edit it in a number dialog.
        // Shows "read / total" when the tracker reports a total (WebUI
        // parity), else just the read count.
        // ---------------------------------------------------------------
        _ChaptersRow(
          label: context.l10n.trackChaptersRead,
          chaptersRead: trackRecord.lastChapterRead,
          totalChapters: trackRecord.totalChapters,
          onSubmit: (val) => _doUpdate(ref, context, () => repo.update(
                recordId: trackRecord.id,
                lastChapterRead: val,
              )),
        ),

        // ---------------------------------------------------------------
        // Start / Finish date rows — only if supportsReadingDates
        // ---------------------------------------------------------------
        if (tracker.supportsReadingDates) ...[
          _DateRow(
            label: context.l10n.trackStartDate,
            date: _epochToDate(trackRecord.startDate),
            onPick: (dt) => _doUpdate(ref, context, () => repo.update(
                  recordId: trackRecord.id,
                  startDate: _dateToEpoch(dt),
                )),
            onClear: () => _doUpdate(ref, context, () => repo.update(
                  recordId: trackRecord.id,
                  startDate: '0',
                )),
          ),
          _DateRow(
            label: context.l10n.trackFinishDate,
            date: _epochToDate(trackRecord.finishDate),
            onPick: (dt) => _doUpdate(ref, context, () => repo.update(
                  recordId: trackRecord.id,
                  finishDate: _dateToEpoch(dt),
                )),
            onClear: () => _doUpdate(ref, context, () => repo.update(
                  recordId: trackRecord.id,
                  finishDate: '0',
                )),
          ),
        ],

        const SizedBox(height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Overflow menu handler
  // ------------------------------------------------------------------

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    TrackerRepository repo,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.togglePrivate:
        await _doUpdate(ref, context, () => repo.update(
              recordId: trackRecord.id,
              private: !trackRecord.private,
            ));

      case _MenuAction.changeEntry:
        if (!context.mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (_) => TrackerSearch(
            mangaId: mangaId,
            mangaTitle: trackRecord.title,
            tracker: tracker,
            onBound: () {
              ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
            },
          ),
        );

      case _MenuAction.remove:
        if (!context.mounted) return;
        final deleteRemote = await _showRemoveDialog(context);
        if (deleteRemote == null) return; // cancelled
        // Re-check context.mounted after the dialog await.
        if (!context.mounted) return;
        await _doUpdate(ref, context, () => repo.unbind(
              recordId: trackRecord.id,
              deleteRemoteTrack: deleteRemote,
            ));
    }
  }

  /// Shows the remove-confirmation dialog.
  /// Returns `null` if cancelled, or `bool` for deleteRemoteTrack.
  Future<bool?> _showRemoveDialog(BuildContext context) async {
    bool deleteRemote = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(ctx.l10n.trackRemoveConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ctx.l10n.trackRemoveConfirmBody(tracker.name)),
              if (tracker.supportsTrackDeletion) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: deleteRemote,
                  onChanged: (v) =>
                      setState(() => deleteRemote = v ?? false),
                  title:
                      Text(ctx.l10n.trackRemoveAlsoOnRemote(tracker.name)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(deleteRemote),
              child: Text(ctx.l10n.remove),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal layout widgets
// ---------------------------------------------------------------------------

enum _MenuAction { togglePrivate, changeEntry, remove }

/// A two-column row: label on the left, [child] filling the right.
class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A date row with a tappable value and an optional clear button.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final void Function(DateTime) onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _EditorRow(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (picked != null) onPick(picked);
              },
              child: Text(
                date != null
                    ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                    : '—',
                style: context.textTheme.bodyMedium,
              ),
            ),
          ),
          if (date != null)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 16),
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

/// A chapters row: shows "read / total" (or just the read count when the
/// tracker reports no total) as a tappable value that opens a number dialog to
/// edit the read count. Mirrors Suwayomi-WebUI's tracker NumberSetting.
class _ChaptersRow extends StatelessWidget {
  const _ChaptersRow({
    required this.label,
    required this.chaptersRead,
    required this.totalChapters,
    required this.onSubmit,
  });

  final String label;
  final double chaptersRead;
  final int totalChapters;
  final void Function(double) onSubmit;

  // Whole numbers show as "12"; fractional chapters keep their decimal.
  String get _readText => chaptersRead == chaptersRead.truncateToDouble()
      ? chaptersRead.toInt().toString()
      : chaptersRead.toString();

  @override
  Widget build(BuildContext context) {
    final display =
        totalChapters > 0 ? '$_readText / $totalChapters' : _readText;
    return _EditorRow(
      label: label,
      child: GestureDetector(
        onTap: () => _edit(context),
        child: Text(display, style: context.textTheme.bodyMedium),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: _readText);
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.trackChaptersRead),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: totalChapters > 0
              ? InputDecoration(suffixText: '/ $totalChapters')
              : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            child: Text(ctx.l10n.save),
          ),
        ],
      ),
    );
    if (result != null && result != chaptersRead) onSubmit(result);
  }
}
