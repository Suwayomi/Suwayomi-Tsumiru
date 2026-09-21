// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'account_storage_recovery.dart';

enum AccountStorageRecoveryPhase { pending, recovering, failed }

class AccountStorageRecoveryState {
  const AccountStorageRecoveryState(
    this.phase, {
    this.completed = 0,
    this.conflicts = const [],
    this.details,
  });

  final AccountStorageRecoveryPhase phase;
  final int completed;
  final String? details;
  final List<AccountProgressConflict> conflicts;
}

final accountStorageRecoveryProvider =
    NotifierProvider<
      AccountStorageRecoveryNotifier,
      AccountStorageRecoveryState?
    >(AccountStorageRecoveryNotifier.new);

class AccountStorageRecoveryNotifier
    extends Notifier<AccountStorageRecoveryState?> {
  @override
  AccountStorageRecoveryState? build() => null;

  void update(AccountStorageRecoveryState? value) => state = value;
}
