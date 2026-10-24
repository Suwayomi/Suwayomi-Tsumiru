// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../widgets/custom_circular_progress_indicator.dart';
import '../../account/data/account_providers.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import 'offline_action_confirmations.dart';

class OfflineSaveButton extends ConsumerWidget {
  const OfflineSaveButton({super.key, required this.chapterId});

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    if (!ref.watch(offlineEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final state =
        ref.watch(offlineChapterStateProvider(chapterId)).value ??
        OfflineDeviceState.none;
    final cs = Theme.of(context).colorScheme;

    return switch (state) {
      OfflineDeviceState.queued => _CancelOnTap(
        chapterId: chapterId,
        child: const _QueuedIndicator(),
      ),
      OfflineDeviceState.downloading => _CancelOnTap(
        chapterId: chapterId,
        child: _DownloadingIndicator(chapterId: chapterId),
      ),
      OfflineDeviceState.downloaded => IconButton(
        tooltip: 'Remove from device',
        icon: Icon(FluentIcons.checkmark_circle_24_filled, color: cs.primary),
        onPressed: () => confirmDeleteChapterFromDevice(ref, chapterId),
      ),
      OfflineDeviceState.error => IconButton(
        tooltip: canDownload
            ? 'Save failed — retry'
            : context.l10n.accountPermissionDenied,
        icon: Icon(FluentIcons.error_circle_24_regular, color: cs.error),
        onPressed: canDownload ? () => _save(context, ref) : null,
      ),
      OfflineDeviceState.none || OfflineDeviceState.orphaned => IconButton(
        tooltip: canDownload
            ? 'Save to device'
            : context.l10n.accountPermissionDenied,
        icon: Icon(FluentIcons.arrow_circle_down_24_regular, color: cs.onSurfaceVariant),
        onPressed: canDownload ? () => _save(context, ref) : null,
      ),
    };
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    try {
      await saveChapterToDevice(ref, chapterId);
    } catch (e) {
      if (context.mounted) {
        // Raw offline errors can contain multi-line socket dumps.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPermissionDenied(e)
                  ? context.l10n.accountPermissionDenied
                  : context.l10n.errorSomethingWentWrong,
            ),
          ),
          snackBarAnimationStyle: context.snackBarMotionStyle,
        );
      }
    }
  }
}

class _CancelOnTap extends ConsumerWidget {
  const _CancelOnTap({required this.chapterId, required this.child});

  final int chapterId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Tooltip(
    message: context.l10n.cancel,
    child: InkResponse(
      radius: Material.defaultSplashRadius,
      onTap: () => deleteChapterFromDevice(ref, chapterId),
      child: child,
    ),
  );
}

// Hundreds of queued rows can coexist; animation would repaint the list every frame.
class _QueuedIndicator extends StatelessWidget {
  const _QueuedIndicator();

  @override
  Widget build(BuildContext context) {
    final box = resolveIconButtonBox(context);
    return SizedBox(
      width: box.width,
      height: box.height,
      child: Center(
        child: Icon(
          FluentIcons.clock_24_regular,
          size: resolveIconButtonIconSize(context),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DownloadingIndicator extends ConsumerWidget {
  const _DownloadingIndicator({required this.chapterId});

  final int chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(offlineChapterProgressProvider(chapterId));
    final value = (progress == null || progress <= 0.0) ? null : progress;
    final box = resolveIconButtonBox(context);
    return SizedBox(
      width: box.width,
      height: box.height,
      child: Center(
        child: SizedBox.square(
          dimension: resolveIconButtonIconSize(context),
          child: CircularProgressIndicator(strokeWidth: 2, value: value),
        ),
      ),
    );
  }
}
