Future<T> withBackgroundScheduleLock<T>(
  Future<T> Function() action, {
  String? baseDir,
  String lockName = '.bg_schedule',
}) => action();
Future<void> reconcileBackgroundSchedule() async {}
