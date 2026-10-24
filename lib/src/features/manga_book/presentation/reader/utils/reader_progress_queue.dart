import 'package:hooks_riverpod/hooks_riverpod.dart';

final readerProgressQueuesProvider = Provider<Map<int, ReaderProgressQueue>>(
  (ref) => {},
);

class ReaderProgressQueue {
  Future<void> _tail = Future.value();
  int generation = 0;
  int _pulls = 0;
  bool get syncing => _pulls > 0;

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> pull<T>(
    Future<T> Function() action, {
    bool Function(T)? replacesProgress,
  }) async {
    _pulls++;
    try {
      return await run(() async {
        final result = await action();
        if (replacesProgress?.call(result) ?? true) generation++;
        return result;
      });
    } finally {
      _pulls--;
    }
  }
}
