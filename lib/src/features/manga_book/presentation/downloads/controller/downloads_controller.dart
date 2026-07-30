import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
    for (final element in [...?downloadStatusDto?.initial]) {
      currState[element.chapter.id] = element;
    }
    for (final element in [...?downloadStatusDto?.updates]) {
      switch (element.type) {
        case DownloadUpdateType.DEQUEUED:
        case DownloadUpdateType.FINISHED:
          currState.remove(element.download.chapter.id);
          break;
        case DownloadUpdateType.QUEUED:
        case DownloadUpdateType.PROGRESS:
        case DownloadUpdateType.POSITION:
        case DownloadUpdateType.PAUSED:
        case DownloadUpdateType.ERROR:
        case DownloadUpdateType.STOPPED:
          currState[element.download.chapter.id] = element.download;
          break;
        case DownloadUpdateType.$unknown:
          throw UnimplementedError();
      }
    }
    if (stateOrNull != null) {
      state = currState;
      _changedSinceFetch = true;
    }
  }

  bool _reconciling = false;
  bool _changedSinceFetch = false;

  /// Re-read the whole queue after the server drops deltas past `maxUpdates`.
  /// Single-flight, and repeats if deltas landed while the request was out —
  /// applying a snapshot older than those deltas would resurrect a chapter the
  /// queue has already lost (#313).
  Future<void> _reconcileQueue() async {
    if (_reconciling) {
      _changedSinceFetch = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _changedSinceFetch = false;
        DownloadStatusDto? fresh;
        try {
          fresh =
              await ref.read(downloadsRepositoryProvider).getDownloadStatus();
        } catch (_) {
          // Transient; the next update message reconciles again.
          return;
        }
        if (!ref.mounted) return;
        if (!_changedSinceFetch) state = getStateFromUpdates(fresh);
      } while (_changedSinceFetch);
    } finally {
      _reconciling = false;
    }
  }

  @override
  Map<int, DownloadDto> build() {
    // The subscription can emit while any widget is mid-build; assigning state
    // synchronously then trips the Riverpod-3 modify-during-build assert
    // app-wide. Defer the write off the current frame.
    ref.listen(downloadUpdatesProvider, (_, next) {
      Future.microtask(() {
        if (!ref.mounted) return;
        // Past `maxUpdates` the server drops the deltas and expects a re-fetch,
        // which any mass en/dequeue trips (#313). Refetch in place rather than
        // invalidating, so the queue doesn't blank out while it reloads.
        if (next.value?.omittedUpdates ?? false) {
          _reconcileQueue();
          return;
        }
        updateDownloadStatus(next.value);
      });
    });
    final downloadStatusDto = ref.watch(downloadStatusProvider).value;
    return getStateFromUpdates(downloadStatusDto);
  }

  Map<int, DownloadDto> getStateFromUpdates(
      DownloadStatusDto? downloadStatusDto) {
    final downloadsMap = <int, DownloadDto>{};
    for (final element in [...?downloadStatusDto?.queue]) {
      downloadsMap[element.chapter.id] = element;
    }
    return downloadsMap;
  }

  void reorder(int chapterId, int to) async {
    final downloadStatusDto = await ref
        .read(downloadsRepositoryProvider)
        .reorderDownload(chapterId, to);
    if (!ref.mounted) return;
    state = getStateFromUpdates(downloadStatusDto);
  }

  /// Clear the whole server download queue and empty the local map immediately.
  /// The clear mutation doesn't reliably emit a per-chapter DEQUEUED stream for
  /// a bulk clear, so without this the list stayed frozen until a manual
  /// refresh (#73). Empty optimistically for instant feedback, then refetch the
  /// authoritative status so a later rebuild can't resurrect the stale queue
  /// from the cached snapshot.
  Future<void> clearAll() async {
    await ref.read(downloadsRepositoryProvider).clearDownloads();
    if (!ref.mounted) return;
    state = {};
    ref.invalidate(downloadStatusProvider);
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

/// Anything queued must be pausable or resumable. Reading the feed's delta list
/// instead hid the control on a fresh subscribe and on any queue that had
/// stopped changing, failed ones included (#313).
@riverpod
bool showDownloadsFAB(Ref ref) => ref.watch(downloadsMapProvider).isNotEmpty;

/// Best-known run state. The feed only speaks when something changes, so a
/// paused queue leaves it with no answer — fall back to the query (#313).
@riverpod
DownloaderState? downloaderRunState(Ref ref) {
  final live = ref.watch(downloadUpdatesProvider).value?.state;
  final queried = ref.watch(downloadStatusProvider).value?.state;
  return live ?? queried;
}
