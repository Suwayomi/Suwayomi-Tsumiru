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
    // Progress ticks arrive about once a second while anything is downloading.
    // A tick that only moves a percentage must not outrank an in-flight
    // re-read, or a round-trip slower than the tick rate could never land and
    // the queue would stay stale for good. A tick that adds a chapter or moves
    // one, though, is a real change and does outrank it.
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

  /// Set once the server tells us it dropped updates, cleared only when a full
  /// re-read has actually landed. Ordinary messages don't carry what was lost,
  /// so until then the queue is known-incomplete and every message retries.
  bool _reconcileNeeded = false;

  /// Bumped by every write that changes which chapters are queued or where.
  /// A re-read that started before the current generation is older than what
  /// we already have, whatever its source.
  int _generation = 0;

  void _publish(Map<int, DownloadDto> queue, {bool structural = true}) {
    state = queue;
    if (structural) _generation++;
  }

  static const _maxReconcileAttempts = 3;
  static const _maxReconcileFailures = 3;

  /// A queue that keeps losing the race is worth retrying on every message; a
  /// server that keeps refusing the read is not, so failures back off instead.
  int _consecutiveFailures = 0;

  /// Re-read the whole queue after the server drops deltas past `maxUpdates`.
  /// Single-flight, and re-reads rather than applying a snapshot that anything
  /// else has since moved past — a clear or a reorder landing mid-flight would
  /// otherwise be undone by the older answer (#313, and the #73 symptom).
  /// [moreDropped] means the server dropped another batch while this read was
  /// out, so the answer in flight is already incomplete and has to be redone.
  /// An ordinary message is not a reason to restart it.
  Future<void> _reconcileQueue({bool moreDropped = false}) async {
    if (moreDropped) _consecutiveFailures = 0;
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
          fresh =
              await ref.read(downloadsRepositoryProvider).getDownloadStatus();
        } catch (_) {
          // _reconcileNeeded stays set, so the next message retries — until
          // the failures say the server, not the race, is the problem.
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
      // Kept losing the race. Stop for now rather than hammering a busy
      // server; _reconcileNeeded is still set, so the next message tries again.
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
    // A rebuild replaces the queue too, so an in-flight re-read must not
    // outrank it. It's also the user's way back in after a run of failures
    // (pull-to-refresh, re-entering the screen), so clear the backoff.
    _generation++;
    _consecutiveFailures = 0;
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
    _publish(getStateFromUpdates(downloadStatusDto));
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
    _publish({});
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
