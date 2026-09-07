Future<T> withBackgroundScheduleLock<T>(
  Future<T> Function() action, {
  String? baseDir,
}) => action();
Future<void> reconcileBackgroundSchedule() async {}
