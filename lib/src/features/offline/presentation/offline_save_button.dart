// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';

/// Save / on-device indicator for a chapter. Hidden on web / when offline is
/// unavailable. The button is shown even for chapters the server hasn't
/// downloaded yet: tapping it cascades a server download first (the server
/// fetches the source), then pulls the device copy — we never scrape sources
/// ourselves (see [saveChapterToDevice]).
class OfflineSaveButton extends ConsumerWidget {
  const OfflineSaveButton({
    super.key,
    required this.chapterId,
  });

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final state = ref
        .watch(offlineChapterStateProvider(chapterId))
        .valueOrNull ??
        OfflineDeviceState.none;
    final cs = Theme.of(context).colorScheme;

    return switch (state) {
      OfflineDeviceState.queued || OfflineDeviceState.downloading =>
        _DownloadingIndicator(chapterId: chapterId),
      OfflineDeviceState.downloaded => IconButton(
          tooltip: 'Remove from device',
          icon: Icon(Icons.offline_pin_rounded, color: cs.primary),
          onPressed: () => deleteChapterFromDevice(ref, chapterId),
        ),
      OfflineDeviceState.error => IconButton(
          tooltip: 'Save failed — retry',
          icon: Icon(Icons.error_outline_rounded, color: cs.error),
          onPressed: () => _save(context, ref),
        ),
      OfflineDeviceState.none || OfflineDeviceState.orphaned => IconButton(
          tooltip: 'Save to device',
          // Muted = a "get it" button (vs the solid-indigo "on device" badge).
          icon: Icon(Icons.save_alt_rounded, color: cs.onSurfaceVariant),
          onPressed: () => _save(context, ref),
        ),
    };
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    try {
      await saveChapterToDevice(ref, chapterId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }
}

/// Determinate download arc for a chapter, showing how many of its pages are
/// on disk. Falls back to an indeterminate
/// spinner until the page total is known.
class _DownloadingIndicator extends ConsumerWidget {
  const _DownloadingIndicator({required this.chapterId});

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(offlineChapterProgressProvider(chapterId)).valueOrNull;
    // Spin (indeterminate) while queued or at 0% so the icon is
    // never invisible; switch to a determinate fill only once pages land.
    final value = (progress == null || progress <= 0.0) ? null : progress;
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, value: value),
        ),
      ),
    );
  }
}
