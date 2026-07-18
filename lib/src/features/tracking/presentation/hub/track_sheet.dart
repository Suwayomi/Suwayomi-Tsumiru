// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../controller/manga_track_records_controller.dart';
import '../../data/graphql/__generated__/query.graphql.dart';
import '../../data/tracker_repository.dart';
import 'widgets/track_editor.dart';
import 'widgets/tracker_search.dart';

/// Opens the tracking hub sheet for [mangaId].
Future<void> showTrackSheet(
  BuildContext context,
  int mangaId, {
  String mangaTitle = '',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => TrackSheetContent(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
    ),
  );
}

/// The body of the tracking hub sheet.
///
/// Watches [trackersProvider] and [mangaTrackRecordsProvider] and renders a card
/// for every logged-in tracker. Trackers that are not logged in are skipped;
/// an empty-state is shown when none are logged in.
class TrackSheetContent extends ConsumerWidget {
  const TrackSheetContent({
    super.key,
    required this.mangaId,
    this.mangaTitle = '',
  });

  final int mangaId;
  final String mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackersAsync = ref.watch(trackersProvider);
    final recordsAsync =
        ref.watch(mangaTrackRecordsProvider(mangaId: mangaId));

    // Surface errors from either provider.
    if (trackersAsync.hasError || recordsAsync.hasError) {
      return _ErrorState(
        message: (trackersAsync.error ?? recordsAsync.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
        },
      );
    }

    // Spinner only on the initial load (no data yet). A reload/retry keeps the
    // current content visible instead of flashing a spinner over it.
    if (!trackersAsync.hasValue || !recordsAsync.hasValue) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final trackers = trackersAsync.value ?? [];
    final records = recordsAsync.value ?? [];
    final loggedIn = trackers.where((t) => t.isLoggedIn).toList();
    final loggedOutBound = trackers.where((t) => !t.isLoggedIn).where(
      (t) => records.any((r) => r.trackerId == t.id),
    ).toList();

    // viewInsets.bottom = keyboard. The Android nav bar reads 0 through
    // MediaQuery padding in this app (so showModalBottomSheet's useSafeArea
    // can't clear it), so pull the real inset from the FlutterView and pad by
    // it, converting physical px -> logical px via devicePixelRatio.
    final view = View.of(context);
    final navBarInset = view.viewPadding.bottom / view.devicePixelRatio;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + navBarInset,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Always-present "Manage trackers" action.
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(context.l10n.manageTrackers),
            onTap: () {
              Navigator.of(context).pop();
              const TrackingSettingsRoute().go(context);
            },
          ),
          const Divider(height: 1),

          // Empty state only when nothing useful to show.
          if (loggedIn.isEmpty && loggedOutBound.isEmpty)
            _EmptyLoginState()
          else ...[
            ...loggedIn.map((tracker) {
              final record = records
                  .firstWhereOrNull((r) => r.trackerId == tracker.id);
              return _TrackerCard(
                tracker: tracker,
                record: record,
                mangaId: mangaId,
                mangaTitle: mangaTitle,
              );
            }),

            // Logged-out trackers that still have a bound record for this manga.
            ...loggedOutBound.map((tracker) {
              final record =
                  records.firstWhereOrNull((r) => r.trackerId == tracker.id);
              return _LoggedOutBoundCard(
                tracker: tracker,
                record: record!,
              );
            }),
          ],

          const SizedBox(height: 16),
        ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

class _EmptyLoginState extends StatelessWidget {
  const _EmptyLoginState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync_disabled_rounded, size: 48),
          const SizedBox(height: 12),
          Text(
            context.l10n.noTrackersLoggedIn,
            style: context.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              const TrackingSettingsRoute().go(context);
            },
            child: Text(context.l10n.manageTrackers),
          ),
        ],
      ),
    );
  }
}

class _TrackerCard extends ConsumerWidget {
  const _TrackerCard({
    required this.tracker,
    required this.record,
    required this.mangaId,
    required this.mangaTitle,
  });

  final Fragment$TrackerDto tracker;
  final Fragment$TrackRecordDto? record;
  final int mangaId;
  final String mangaTitle;

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final rec = record;
    if (rec == null) return;
    await AppUtils.guard(
      () => ref.read(trackerRepositoryProvider).fetch(rec.id),
      ref.read(toastProvider),
    );
    if (context.mounted) {
      ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = record;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tracker header row.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Image.network(
                  tracker.icon,
                  width: 24,
                  height: 24,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.sync_rounded, size: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracker.name,
                    style: context.textTheme.titleSmall,
                  ),
                ),
                if (rec != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: context.l10n.refresh,
                    onPressed: () => _refresh(context, ref),
                  ),
              ],
            ),
          ),

          // Card body: add / edit / login-required.
          if (rec == null)
            // No record — offer to bind.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: OutlinedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (_) => TrackerSearch(
                    mangaId: mangaId,
                    mangaTitle: mangaTitle,
                    tracker: tracker,
                    onBound: () {
                      ref.invalidate(
                          mangaTrackRecordsProvider(mangaId: mangaId));
                    },
                  ),
                ),
                child: Text(context.l10n.addTracking),
              ),
            )
          else
            // Bound record — show editor.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              child: TrackEditor(
                tracker: tracker,
                trackRecord: rec,
                mangaId: mangaId,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoggedOutBoundCard extends StatelessWidget {
  const _LoggedOutBoundCard({
    required this.tracker,
    required this.record,
  });

  final Fragment$TrackerDto tracker;
  final Fragment$TrackRecordDto record;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tracker header row.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Image.network(
                  tracker.icon,
                  width: 24,
                  height: 24,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.sync_rounded, size: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracker.name,
                    style: context.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),

          // Read-only bound title + login prompt.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  record.title,
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    const TrackingSettingsRoute().go(context);
                  },
                  child: Text(context.l10n.logInToEdit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(context.l10n.refresh),
          ),
        ],
      ),
    );
  }
}
