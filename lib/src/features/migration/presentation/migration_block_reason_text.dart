// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../l10n/generated/app_localizations.dart';
import '../domain/bulk_migration_types.dart';

String? migrationBlockReasonText(AppLocalizations l10n, BulkMigrationEntry e) {
  switch (e.blockKind) {
    case null:
      return null;
    case MigrationBlockKind.selfTarget:
      return l10n.migrationBlockedSelfTarget;
    case MigrationBlockKind.sourceChaptersUnavailable:
      return l10n.migrationBlockedChaptersUnavailable(
        e.fromSourceName ?? l10n.unknownSource,
      );
    case MigrationBlockKind.targetChaptersUnavailable:
      return l10n.migrationBlockedChaptersUnavailable(
        e.toSourceName ?? l10n.unknownSource,
      );
    case MigrationBlockKind.targetEmpty:
      return l10n.migrationBlockedNoChapters(
        e.toSourceName ?? l10n.unknownSource,
      );
    case MigrationBlockKind.unmatchedState:
      return l10n.migrationBlockedUnmatched(
        e.toUnmatchedState,
        e.toSourceName ?? l10n.unknownSource,
      );
  }
}

String? migrationFailureText(AppLocalizations l10n, BulkMigrationEntry e) {
  switch (e.failureKind) {
    case null:
      return null;
    case MigrationFailureKind.unsyncedReads:
      return l10n.migrationFailureUnsyncedReads;
    case MigrationFailureKind.copyFailed:
      return l10n.migrationFailureCopyFailed;
    case MigrationFailureKind.removalFailed:
      return l10n.migrationFailureRemovalFailed;
  }
}
