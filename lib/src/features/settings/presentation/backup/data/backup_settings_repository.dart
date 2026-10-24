// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../account/data/account_permission.dart';
import '../../../domain/settings/settings.dart';
import '../widgets/backup_flags/backup_flags.dart';
import './graphql/__generated__/query.graphql.dart';

part 'backup_settings_repository.g.dart';

class BackupSettingsRepository {
  const BackupSettingsRepository(this.ferryClient, {required this.permissions});

  final AccountPermissionGuard permissions;

  final GraphQLClient ferryClient;

  Future<String?> restoreBackup(MultipartFile file, BackupFlags flags) async {
    final supported = await userSettingsFlag() != null;
    return ferryClient
        .mutate$RestoreBackup(
          Options$Mutation$RestoreBackup(
            variables: Variables$Mutation$RestoreBackup(
              backup: file,
              flags: flags.toPartialInput(supportsUserSettings: supported),
            ),
          ),
        )
        .getData((data) => data.restoreBackup.id);
  }

  Future<bool?> userSettingsFlag() async {
    try {
      return await ferryClient
          .query$BackupUserSettingsCapability(
            Options$Query$BackupUserSettingsCapability(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings.autoBackupIncludeUserSettings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$AutoBackupFlagsDto?> autoBackupFlags() async {
    try {
      return await ferryClient
          .query$AutoBackupFlags(
            Options$Query$AutoBackupFlags(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$AutoBackupFlagsDto?> updateAutoBackupFlags(
    BackupFlags flags,
  ) => permissions.run(Enum$UserPermission.MANAGE_SETTINGS, () async {
    final supported = await userSettingsFlag() != null;
    return ferryClient
        .mutate$UpdateAutoBackupFlags(
          Options$Mutation$UpdateAutoBackupFlags(
            variables: Variables$Mutation$UpdateAutoBackupFlags(
              settings: flags.toAutoInput(supportsUserSettings: supported),
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
  });

  Future<Set<String>?> validateBackup(MultipartFile file) => ferryClient
      .query$ValidateBackup(
        Options$Query$ValidateBackup(
          variables: Variables$Query$ValidateBackup(backup: file),
        ),
      )
      .getData(
        (data) => data.validateBackup.missingSources
            .map((value) => value.name)
            .toSet(),
      );

  Future<RestoreStatusDto?> getRestoreStatus(String restoreId) => ferryClient
      .query$RestoreStatus(
        Options$Query$RestoreStatus(
          variables: Variables$Query$RestoreStatus(restoreId: restoreId),
        ),
      )
      .getData((data) => data.restoreStatus);

  Future<String?> createBackup(BackupFlags flags) async {
    final supported = await userSettingsFlag() != null;
    return ferryClient
        .mutate$CreateBackup(
          Options$Mutation$CreateBackup(
            variables: Variables$Mutation$CreateBackup(
              flags: flags.toPartialInput(supportsUserSettings: supported),
            ),
          ),
        )
        .getData((data) => data.createBackup.url);
  }

  Future<SettingsDto?> updateBackupLocation(String? backupPath) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateBackupPath(
              Options$Mutation$UpdateBackupPath(
                variables: Variables$Mutation$UpdateBackupPath(
                  backupPath: backupPath.ifBlank(),
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateBackupTime(TimeOfDay backupTime) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateBackupTime(
              Options$Mutation$UpdateBackupTime(
                variables: Variables$Mutation$UpdateBackupTime(
                  backupTime: backupTime.hhmm,
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateBackupInterval(int backupInterval) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateBackupInterval(
              Options$Mutation$UpdateBackupInterval(
                variables: Variables$Mutation$UpdateBackupInterval(
                  backupInterval: backupInterval,
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateBackupTTL(int backupTTL) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateBackupTTL(
          Options$Mutation$UpdateBackupTTL(
            variables: Variables$Mutation$UpdateBackupTTL(backupTTL: backupTTL),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

@riverpod
BackupSettingsRepository backupSettingsRepository(Ref ref) =>
    BackupSettingsRepository(
      ref.watch(graphQlClientProvider),
      permissions: ref.watch(accountPermissionGuardProvider),
    );

final autoBackupFlagsProvider =
    FutureProvider.autoDispose<Fragment$AutoBackupFlagsDto?>(
      (ref) => ref.watch(backupSettingsRepositoryProvider).autoBackupFlags(),
    );

final backupUserSettingsProvider = FutureProvider.autoDispose<bool?>(
  (ref) => ref.watch(backupSettingsRepositoryProvider).userSettingsFlag(),
);
