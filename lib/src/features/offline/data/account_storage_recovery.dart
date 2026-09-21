// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

class AccountStorageRecoveryRequired extends StateError {
  AccountStorageRecoveryRequired() : super('Offline downloads need recovery');
}

class AccountStorageRecovery {
  AccountStorageRecovery({
    required this.isCurrent,
    required this.onProgress,
    this.progressChoices = const {},
  });

  final Map<int, bool> progressChoices;

  final bool Function() isCurrent;
  final void Function(int completed) onProgress;
  int _completed = 0;
  final _updates = Stopwatch()..start();

  void check() {
    if (!isCurrent()) throw StateError('Account storage recovery cancelled');
  }

  void completed() {
    check();
    _completed++;
    if (_completed == 1 || _updates.elapsedMilliseconds >= 250) {
      onProgress(_completed);
      _updates.reset();
    }
  }
}

class AccountStorageProgressConflict extends StateError {
  AccountStorageProgressConflict(this.conflicts)
    : super(
        'Reading progress differs between the original and current catalogues',
      );

  final List<AccountProgressConflict> conflicts;
}

class AccountProgressConflict {
  const AccountProgressConflict({
    required this.chapterId,
    required this.name,
    required this.originalPage,
    required this.currentPage,
    required this.originalRead,
    required this.currentRead,
    required this.originalBookmarked,
    required this.currentBookmarked,
    this.originalLastReadAt,
    this.currentLastReadAt,
    this.originalPendingFields = const [],
    this.currentPendingFields = const [],
    this.originalReadStateManual = false,
    this.currentReadStateManual = false,
  });

  final int chapterId;
  final String name;
  final int originalPage;
  final int currentPage;
  final bool originalRead;
  final bool currentRead;
  final bool originalBookmarked;
  final bool currentBookmarked;
  final String? originalLastReadAt;
  final String? currentLastReadAt;
  final List<String> originalPendingFields;
  final List<String> currentPendingFields;
  final bool originalReadStateManual;
  final bool currentReadStateManual;
}
