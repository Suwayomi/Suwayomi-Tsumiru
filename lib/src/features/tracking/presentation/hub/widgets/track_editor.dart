// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/hover_tap_target.dart';
import '../../../../../widgets/server_image.dart';
import '../../../controller/manga_track_records_controller.dart';
import '../../../data/graphql/__generated__/query.graphql.dart';
import '../../../data/tracker_repository.dart';
import 'tracker_search.dart';

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


  Future<void> _doUpdate(
    WidgetRef ref,
    BuildContext context,
    Future<void> Function() mutation,
  ) async {
    final result = await AsyncValue.guard(mutation);
    // Both branches use ref; the sheet may have been dismissed during the mutation.
    if (!context.mounted) return;
    if (result.hasError) {
      result.showToastOnError(ref.read(toastProvider));
      ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
      return;
    }
    ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
  }


  /// Server epoch milliseconds; "0" means unset.
  static DateTime? _epochToDate(String epochMs) {
    if (epochMs == '0' || epochMs.isEmpty) return null;
    final ms = int.tryParse(epochMs);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Stores local midnight as epoch milliseconds.
  static String _dateToEpoch(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day)
          .millisecondsSinceEpoch
          .toString();


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(trackerRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              ServerImage(
                imageUrl: tracker.icon,
                size: const Size.square(20),
                progressIndicatorBuilder: (_, _, _) =>
                    const Icon(FluentIcons.arrow_sync_24_regular, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HoverTapTarget(
                  builder: (context, hovered) => GestureDetector(
                    onTap: () => launchUrlInWeb(
                      context,
                      trackRecord.remoteUrl,
                      ref.read(toastProvider),
                    ),
                    child: Text(
                      trackRecord.title,
                      style: context.textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.underline,
                        color: hovered
                            ? context.theme.colorScheme.primary
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              PopupMenuButton<_MenuAction>(
                icon: const Icon(FluentIcons.more_vertical_24_regular),
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
                popUpAnimationStyle: context.motionStyle,
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        _EditorRow(
          label: context.l10n.trackStatus,
          child: DropdownButton<int>(
            icon: const Icon(
              FluentIcons.caret_down_24_filled,
            ),
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

        _EditorRow(
          label: context.l10n.trackScore,
          child: DropdownButton<String>(
            icon: const Icon(
              FluentIcons.caret_down_24_filled,
            ),
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

        _ChaptersRow(
          label: context.l10n.trackChaptersRead,
          chaptersRead: trackRecord.lastChapterRead,
          totalChapters: trackRecord.totalChapters,
          onSubmit: (val) => _doUpdate(ref, context, () => repo.update(
                recordId: trackRecord.id,
                lastChapterRead: val,
              )),
        ),

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
          sheetAnimationStyle: context.motionStyle,
        );

      case _MenuAction.remove:
        if (!context.mounted) return;
        final deleteRemote = await _showRemoveDialog(context);
        if (deleteRemote == null) return; // cancelled
        if (!context.mounted) return;
        await _doUpdate(ref, context, () => repo.unbind(
              recordId: trackRecord.id,
              deleteRemoteTrack: deleteRemote,
            ));
    }
  }

  /// null cancels; otherwise the result selects whether to delete the remote track too.
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
      animationStyle: context.motionStyle,
    );
  }
}


enum _MenuAction { togglePrivate, changeEntry, remove }

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
            child: HoverTapTarget(
              builder: (context, hovered) => GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                    switchToInputEntryModeIcon: const Icon(
                      FluentIcons.edit_24_regular,
                    ),
                    switchToCalendarEntryModeIcon: const Icon(
                      FluentIcons.calendar_24_regular,
                    ),
                  );
                  if (picked != null) onPick(picked);
                },
                child: Text(
                  date != null
                      ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                      : '—',
                  style: context.textTheme.bodyMedium?.copyWith(
                    decoration: hovered
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          if (date != null)
            IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

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

  String get _readText => chaptersRead == chaptersRead.truncateToDouble()
      ? chaptersRead.toInt().toString()
      : chaptersRead.toString();

  @override
  Widget build(BuildContext context) {
    final display = totalChapters > 0
        ? '$_readText / $totalChapters'
        : _readText;
    return _EditorRow(
      label: label,
      child: HoverTapTarget(
        builder: (context, hovered) => GestureDetector(
          onTap: () => _edit(context),
          child: Text(
            display,
            style: context.textTheme.bodyMedium?.copyWith(
              decoration: hovered
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        ),
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
      animationStyle: context.motionStyle,
    );
    if (result != null && result != chaptersRead) onSubmit(result);
  }
}
