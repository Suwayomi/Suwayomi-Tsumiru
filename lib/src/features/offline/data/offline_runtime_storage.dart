import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';

typedef OfflineStorage = ({
  OfflineDatabase db,
  OfflinePaths paths,
  OfflinePageStore store,
});

final offlineRuntimeStorageProvider =
    NotifierProvider<OfflineRuntimeStorage, OfflineStorage?>(
      OfflineRuntimeStorage.new,
    );

class OfflineRuntimeStorage extends Notifier<OfflineStorage?> {
  bool _switching = false;
  final _pending = <Future<void>>{};

  @override
  OfflineStorage? build() => null;

  Future<T> track<T>(Future<T> Function() action) async {
    final finished = Completer<void>();
    _pending.add(finished.future);
    try {
      return await action();
    } finally {
      finished.complete();
      _pending.remove(finished.future);
    }
  }

  Future<void> drain({Duration timeout = const Duration(seconds: 3)}) =>
      whenIdle().timeout(timeout);

  Future<void> whenIdle() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  OfflineStorage? take() {
    if (_switching || _pending.isNotEmpty) {
      throw StateError('Offline storage still has pending work');
    }
    final previous = state;
    state = null;
    return previous;
  }

  Future<void> replace({
    required Future<void> Function() drain,
    required Future<OfflineStorage?> Function() open,
    void Function()? onDetached,
  }) async {
    if (_switching) throw StateError('Offline storage is changing');
    _switching = true;
    try {
      await drain();
      final previous = state;
      state = null;
      onDetached?.call();
      await previous?.db.close();
      state = await open();
    } finally {
      _switching = false;
    }
  }
}
