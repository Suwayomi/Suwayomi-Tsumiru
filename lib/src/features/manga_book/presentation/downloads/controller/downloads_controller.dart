import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/downloads/downloads_model.dart';
import '../../../domain/downloads/graphql/__generated__/fragment.graphql.dart';
import '../../../domain/downloads_queue/downloads_queue_model.dart';

part 'downloads_controller.g.dart';

@riverpod
Stream<DownloadUpdatesDto?> downloadUpdates(Ref ref) =>
    ref.watch(downloadsRepositoryProvider).downloadStatusSubscription();

@riverpod
Future<DownloadStatusDto?> downloadStatus(Ref ref) =>
    ref.watch(downloadsRepositoryProvider).getDownloadStatus();

@riverpod
class DownloadsMap extends _$DownloadsMap {
  void updateDownloadStatus(Fragment$DownloadUpdatesDto? downloadStatusDto) {
    final currState = {...?stateOrNull};
    // Only structural queue changes supersede a re-read; percentage ticks must not starve it.
    var structural = downloadStatusDto?.initial?.isNotEmpty ?? false;
    for (final element in [...?downloadStatusDto?.initial]) {
      currState[element.chapter.id] = element;
    }
    for (final element in [...?downloadStatusDto?.updates]) {
      final chapterId = element.download.chapter.id;
      switch (element.type) {
        case DownloadUpdateType.DEQUEUED:
        case DownloadUpdateType.FINISHED:
          structural = true;
          currState.remove(chapterId);
          break;
        case DownloadUpdateType.PROGRESS:
          final previous = currState[chapterId];
          if (previous == null ||
              previous.position != element.download.position) {
            structural = true;
          }
          currState[chapterId] = element.download;
          break;
        case DownloadUpdateType.QUEUED:
        case DownloadUpdateType.POSITION:
        case DownloadUpdateType.PAUSED:
        case DownloadUpdateType.ERROR:
        case DownloadUpdateType.STOPPED:
          structural = true;
          currState[chapterId] = element.download;
          break;
        case DownloadUpdateType.$unknown:
          throw UnimplementedError();
      }
    }
    if (stateOrNull != null) {
      _publish(currState, structural: structural);
    }
  }

  bool _reconciling = false;
  bool _restartRequested = false;

  /// Keep reconciliation pending until a full re-read lands; ordinary deltas cannot recover lost updates.
  bool _reconcileNeeded = false;

  /// Structural writes invalidate snapshots captured by an earlier generation.
  int _generation = 0;

  void _publish(Map<int, DownloadDto> queue, {bool structural = true}) {
    state = queue;
    if (structural) _generation++;
  }

  static const _maxReconcileAttempts = 3;
  static const _maxReconcileFailures = 3;

  /// Back off failed reads; retrying a superseded snapshot is safe.
  int _consecutiveFailures = 0;

  /// Single-flight re-read after dropped deltas; reject stale snapshots and repeat if [moreDropped].
  Future<void> _reconcileQueue({bool moreDropped = false}) async {
    // Dropped deltas do not imply server recovery, so preserve failure backoff.
    if (_consecutiveFailures >= _maxReconcileFailures) return;
    if (_reconciling) {
      if (moreDropped) _restartRequested = true;
      return;
    }
    _reconciling = true;
    try {
      for (var attempt = 0; attempt < _maxReconcileAttempts; attempt++) {
        _restartRequested = false;
        final generation = _generation;
        DownloadStatusDto? fresh;
        try {
          fresh = await ref
              .read(downloadsRepositoryProvider)
              .getDownloadStatus();
        } catch (_) {
          // Leave reconciliation pending for retries until the failure limit is reached.
          _consecutiveFailures++;
          return;
        }
        if (!ref.mounted) return;
        if (generation == _generation && !_restartRequested) {
          _publish(getStateFromUpdates(fresh));
          _consecutiveFailures = 0;
          _reconcileNeeded = false;
          return;
        }
      }
      // Leave reconciliation pending for the next message instead of retrying indefinitely.
    } finally {
      _reconciling = false;
    }
  }

  @override
  Map<int, DownloadDto> build() {
    // Defer subscription writes because emissions can arrive during widget build.
    ref.listen(downloadUpdatesProvider, (_, next) {
      Future.microtask(() {
        if (!ref.mounted) return;
        // Past maxUpdates the server drops deltas; refetch in place to keep the queue visible.
        final dropped = next.value?.omittedUpdates ?? false;
        if (dropped) {
          _reconcileNeeded = true;
        } else {
          updateDownloadStatus(next.value);
        }
        if (_reconcileNeeded) _reconcileQueue(moreDropped: dropped);
      });
    });
    final downloadStatusDto = ref.watch(downloadStatusProvider).value;
    // A rebuild supersedes in-flight reads and resets failure backoff for an explicit retry.
    _generation++;
    _consecutiveFailures = 0;
    return getStateFromUpdates(downloadStatusDto);
  }

  Map<int, DownloadDto> getStateFromUpdates(
    DownloadStatusDto? downloadStatusDto,
  ) {
    final downloadsMap = <int, DownloadDto>{};
    for (final element in [...?downloadStatusDto?.queue]) {
      downloadsMap[element.chapter.id] = element;
    }
    return downloadsMap;
  }

  Future<void> reorder(int chapterId, int to) async {
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    final result = await AsyncValue.guard(
      () =>
          ref.read(downloadsRepositoryProvider).reorderDownload(chapterId, to),
    );
    if (!ref.mounted || !current()) return;
    if (result.hasError) {
      result.showToastOnError(ref.read(toastProvider));
    } else {
      _publish(getStateFromUpdates(result.value));
    }
  }

  /// Bulk clear may omit DEQUEUED events; clear locally and refetch the authoritative queue.
  Future<void> clearAll() async {
    await ref.read(downloadsRepositoryProvider).clearDownloads();
    if (!ref.mounted) return;
    _publish({});
    ref.invalidate(downloadStatusProvider);
  }

  /// Dequeues [chapterIds]; survivors are still requested by another account.
  Future<Set<int>> cancelQueuedChapters(List<int> chapterIds) async {
    final repo = ref.read(downloadsRepositoryProvider);
    for (final id in chapterIds) {
      await repo.removeChapterFromDownloadQueue(id);
    }
    final fresh = await repo.getDownloadStatus();
    if (ref.mounted && fresh != null) _publish(getStateFromUpdates(fresh));
    final remaining = stateOrNull ?? const <int, DownloadDto>{};
    return {for (final id in chapterIds) if (remaining.containsKey(id)) id};
  }
}

@riverpod
DownloadDto? downloadsFromId(Ref ref, int chapterId) =>
    ref.watch(downloadsMapProvider.select((map) => map[chapterId]));

@riverpod
List<int> downloadsChapterIds(Ref ref) {
  final downloads = ref.watch(downloadsMapProvider).values.toList();
  downloads.sort((a, b) => a.position.compareTo(b.position));
  return downloads.map((d) => d.chapter.id).toList();
}

@riverpod
bool manageAllDownloads(Ref ref) {
  final access = ref.watch(settledAccountAccessProvider);
  return access.canManageUsers ||
      access.capability == AccountCapability.unsupported;
}

@riverpod
({bool manageAll, List<int> mineIds, List<int> visibleIds})
downloadsVisibility(Ref ref) {
  final manageAll = ref.watch(manageAllDownloadsProvider);
  final ordered = ref.watch(downloadsChapterIdsProvider);
  final map = ref.watch(downloadsMapProvider);
  final mineIds = [
    for (final id in ordered)
      if (map[id]?.manga.user.inLibrary ?? manageAll) id,
  ];
  return (
    manageAll: manageAll,
    mineIds: mineIds,
    visibleIds: manageAll ? ordered : mineIds,
  );
}

@riverpod
bool showDownloadsFAB(Ref ref) => ref.watch(downloadsMapProvider).isNotEmpty;

/// A paused queue may emit no run state; fall back to the query.
@riverpod
DownloaderState? downloaderRunState(Ref ref) {
  final live = ref.watch(downloadUpdatesProvider).value?.state;
  final queried = ref.watch(downloadStatusProvider).value?.state;
  return live ?? queried;
}
