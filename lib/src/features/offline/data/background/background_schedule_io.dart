import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../../notifications/data/background/notification_background_entry.dart';
import '../../../notifications/data/notification_state_store.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
import 'catchup_work_spec.dart';

Future<String> _baseDir() async =>
    '${(await getApplicationSupportDirectory()).path}/offline';

Future<T> withBackgroundScheduleLock<T>(
  Future<T> Function() action, {
  String? baseDir,
}) async {
  final lock = BackgroundDownloadLock(
    File('${baseDir ?? await _baseDir()}/.bg_schedule'),
  );
  for (var i = 0; i < 600; i++) {
    if (await lock.acquire('schedule')) {
      try {
        return await action();
      } finally {
        await lock.release();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Background download schedule is busy');
}

Future<void> reconcileBackgroundSchedule() =>
    withBackgroundScheduleLock(() async {
      final notifications = await NotificationStateStore.open();
      final config = notifications.readConfig();
      final state = await CatchupStateStore.open();
      final spec = state.readSpec();
      final valid =
          spec != null &&
          spec.serverId == state.catalogServerId &&
          config != null &&
          state.matchesIdentity(config);
      var queue = false;
      if (valid && !state.paused) {
        final entries = await BackgroundCompletionLog(
          File('${await _baseDir()}/.bg_completion.log'),
        ).parse();
        queue = spec.queuedChapters.any(
          (chapter) => !queuedChapterTerminal(entries, chapter),
        );
      }
      final catchup =
          valid && !state.paused && state.enabled && spec.manga.isNotEmpty;
      final notices = config?.anyEnabled ?? false;
      if (!queue && !catchup && !notices) {
        await Workmanager().cancelByUniqueName(kNewChapterPeriodicName);
        return;
      }
      final downloadDemand = queue || catchup;
      final wifiOnly =
          (!notices || config!.wifiOnly) && (!downloadDemand || spec!.wifiOnly);
      await Workmanager().registerPeriodicTask(
        kNewChapterPeriodicName,
        kNewChapterCheckTask,
        frequency: Duration(hours: (config?.intervalHours ?? 6).clamp(1, 6)),
        constraints: Constraints(
          networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresCharging: !downloadDemand && (config?.chargingOnly ?? false),
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    });

bool queuedChapterTerminal(List<LogEntry> entries, QueuedChapterSpec chapter) {
  var generation = -1;
  String? status;
  for (final entry in entries) {
    if (entry is DeletedEntry &&
        entry.chapterId == chapter.chapterId &&
        entry.generation >= generation) {
      generation = entry.generation;
      status = null;
    }
    if (entry is ChapterEntry &&
        entry.chapterId == chapter.chapterId &&
        entry.generation >= generation) {
      generation = entry.generation;
      status = entry.status;
    }
  }
  return generation == chapter.generation &&
      (status == 'downloaded' || status == 'error');
}
