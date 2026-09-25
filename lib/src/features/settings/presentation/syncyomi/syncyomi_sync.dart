import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../data/user_settings.dart';
import 'data/syncyomi_settings_repository.dart';
import 'domain/sync_yomi.dart';

/// Wording for the step a running sync has reached.
String syncYomiStepName(BuildContext context, SyncYomiStep step) {
  final l10n = context.l10n;
  return switch (step) {
    SyncYomiStep.starting => l10n.syncYomiStepStarting,
    SyncYomiStep.creatingBackup => l10n.syncYomiStepCreatingBackup,
    SyncYomiStep.downloading => l10n.syncYomiStepDownloading,
    SyncYomiStep.merging => l10n.syncYomiStepMerging,
    SyncYomiStep.uploading => l10n.syncYomiStepUploading,
    SyncYomiStep.restoring => l10n.syncYomiStepRestoring,
    SyncYomiStep.unknown => l10n.syncYomiSyncing,
  };
}

class SyncYomiSync {
  const SyncYomiSync({
    required this.view,
    required this.step,
    required this.running,
    required this.start,
  });

  final SyncYomiStatusView view;
  final SyncYomiStep step;
  final bool running;
  final Future<void> Function() start;
}

/// Starts a sync and watches it, shared by the settings screen's Sync now row
/// and the Library and Updates top bars.
///
/// [onSynced] runs once when a sync this app started or watched run reaches
/// SUCCESS, so callers can re-read what the sync changed. An old SUCCESS the
/// server was already reporting when the widget mounted does not qualify.
SyncYomiSync useSyncYomi(WidgetRef ref, {VoidCallback? onSynced}) {
  final context = useContext();
  final l10n = context.l10n;
  final repository = ref.watch(syncyomiSettingsRepositoryProvider);
  final status = ref.watch(lastSyncStatusProvider);
  final view = syncYomiStatusView(
    state: status.value?.state.name,
    endDate: status.value?.endDate,
    errorMessage: status.value?.errorMessage,
  );
  final terminal =
      view.kind == SyncYomiStatusKind.synced ||
      view.kind == SyncYomiStatusKind.failed;
  final requested = useState(false);
  final sawRunning = useRef(false);
  final poll =
      !terminal && (requested.value || view.kind == SyncYomiStatusKind.syncing);

  // Poll only while a sync is actually in flight, capped at ten minutes.
  useEffect(() {
    if (!poll) return null;
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    final timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        return;
      }
      ref.invalidate(lastSyncStatusProvider);
    });
    return timer.cancel;
  }, [poll]);

  useEffect(() {
    if (!terminal) {
      if (view.kind == SyncYomiStatusKind.syncing) sawRunning.value = true;
      return null;
    }
    if (view.kind == SyncYomiStatusKind.synced && sawRunning.value) {
      sawRunning.value = false;
      onSynced?.call();
    }
    return null;
  }, [terminal, view.kind]);

  Future<void> start() async {
    final result = await AppUtils.guard(
      repository.startSync,
      ref.read(toastProvider),
    );
    if (result == null || !context.mounted) return;
    final toast = ref.read(toastProvider);
    switch (result) {
      case Enum$StartSyncResult.SUCCESS:
        toast?.show(l10n.syncYomiSyncStarted);
        sawRunning.value = true;
        requested.value = true;
      case Enum$StartSyncResult.SYNC_IN_PROGRESS:
        toast?.show(l10n.syncYomiAlreadyRunning);
        sawRunning.value = true;
        requested.value = true;
      case Enum$StartSyncResult.SYNC_DISABLED:
        toast?.show(l10n.syncYomiDisabled);
      case Enum$StartSyncResult.$unknown:
        break;
    }
    if (requested.value) ref.invalidate(lastSyncStatusProvider);
  }

  return SyncYomiSync(
    view: view,
    step: syncYomiStep(status.value?.state.name),
    running:
        view.kind == SyncYomiStatusKind.syncing ||
        (requested.value && !terminal),
    start: start,
  );
}

/// Top-bar sync action. Draws nothing unless SyncYomi is on and configured.
class SyncYomiSyncButton extends ConsumerWidget {
  const SyncYomiSyncButton({super.key, this.onSynced});

  final VoidCallback? onSynced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(personalSettingsProvider).value;
    if (settings == null ||
        !settings.syncYomiEnabled ||
        settings.syncYomiHost.isBlank ||
        settings.syncYomiApiKey.isBlank) {
      return const SizedBox.shrink();
    }
    return _SyncYomiSyncAction(onSynced: onSynced);
  }
}

class _SyncYomiSyncAction extends HookConsumerWidget {
  const _SyncYomiSyncAction({this.onSynced});

  final VoidCallback? onSynced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = useSyncYomi(ref, onSynced: onSynced);
    if (sync.running) {
      return IconButton(
        tooltip: syncYomiStepName(context, sync.step),
        icon: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        onPressed: null,
      );
    }
    return IconButton(
      icon: const Icon(Icons.cloud_sync_rounded),
      tooltip: context.l10n.syncYomiSyncNow,
      onPressed: sync.start,
    );
  }
}
