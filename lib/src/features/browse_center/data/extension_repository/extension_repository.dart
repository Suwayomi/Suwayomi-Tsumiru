// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../account/data/account_permission.dart';
import '../../domain/extension/extension_model.dart';
import './graphql/__generated__/query.graphql.dart';
import './graphql/__generated__/store_query.graphql.dart';
import './store_extension_mapper.dart';

part 'extension_repository.g.dart';

class ExtensionRepository {
  final GraphQLClient client;

  ExtensionRepository(this.client, {required this.permissions});

  final AccountPermissionGuard permissions;

  Future<void> installExtensionFile(
    BuildContext context, {
    PlatformFile? file,
  }) async {
    permissions.require(Enum$UserPermission.INSTALL_EXTERNAL_EXTENSIONS);
    if ((file?.name).isBlank) {
      throw context.l10n.errorFilePick;
    }
    if (!(file!.name.endsWith('.apk'))) {
      throw context.l10n.errorFilePickUnknownExtension(".apk");
    }
    final upload = kIsWeb
        ? http.MultipartFile.fromBytes(
            'extensionFile',
            await file.readAsBytes(),
            filename: file.name,
          )
        : await http.MultipartFile.fromPath('extensionFile', file.path!);
    permissions.require(Enum$UserPermission.INSTALL_EXTERNAL_EXTENSIONS);
    await client
        .mutate$InstallExternalExtension(
          Options$Mutation$InstallExternalExtension(
            variables: Variables$Mutation$InstallExternalExtension(
              extensionFile: upload,
            ),
          ),
        )
        .getData((data) => null);
  }

  Future<void> installExtension(String pkgName) => permissions.run(
    Enum$UserPermission.INSTALL_EXTENSIONS,
    () => client
        .mutate$UpdateExtension(
          Options$Mutation$UpdateExtension(
            variables: Variables$Mutation$UpdateExtension(
              id: pkgName,
              install: true,
            ),
          ),
        )
        .getData((data) {}),
  );

  Future<void> uninstallExtension(String pkgName) => permissions.run(
    Enum$UserPermission.UNINSTALL_EXTENSIONS,
    () => client
        .mutate$UpdateExtension(
          Options$Mutation$UpdateExtension(
            variables: Variables$Mutation$UpdateExtension(
              id: pkgName,
              uninstall: true,
            ),
          ),
        )
        .getData((data) {}),
  );

  Future<void> updateExtension(String pkgName) => client
      .mutate$UpdateExtension(
        Options$Mutation$UpdateExtension(
          variables: Variables$Mutation$UpdateExtension(
            id: pkgName,
            update: true,
          ),
        ),
      )
      .getData((data) {});

  /// How many installed extensions have an update waiting.
  ///
  /// A plain query, unlike [getExtensionListStream] — that one is a mutation
  /// that sends the server out to the extension repos, which is far too much to
  /// do for a number on a navigation bar.
  Future<int> getExtensionUpdateCount() => client
      .query$ExtensionUpdateCount(
        Options$Query$ExtensionUpdateCount(
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      )
      .getData((data) => data.extensions.totalCount)
      .then((value) => value ?? 0);

  Future<List<Extension>?> getExtensionListStream() =>
      client.mutate$FetchExtensionListStore().getData(
        (data) => data.fetchExtensions?.extensions
            .map(extensionFromStoreDto)
            .toList(),
      );
}

@riverpod
ExtensionRepository extensionRepository(Ref ref) => ExtensionRepository(
  ref.watch(graphQlClientProvider),
  permissions: ref.watch(accountPermissionGuardProvider),
);
