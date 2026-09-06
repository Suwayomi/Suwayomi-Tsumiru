// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension/extension_model.dart';

GraphQLClient dummyGraphQLClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// Records every mutation the app sends; [calls] keeps their order.
class FakeExtensionRepository extends ExtensionRepository {
  FakeExtensionRepository() : super(dummyGraphQLClient());

  final List<String> installed = <String>[];
  final List<String> uninstalled = <String>[];
  final List<String> updated = <String>[];
  final List<PlatformFile> fileInstalls = <PlatformFile>[];
  final List<String> calls = <String>[];

  @override
  Future<void> installExtension(String pkgName) async {
    installed.add(pkgName);
    calls.add('install $pkgName');
  }

  @override
  Future<void> uninstallExtension(String pkgName) async {
    uninstalled.add(pkgName);
    calls.add('uninstall $pkgName');
  }

  @override
  Future<void> updateExtension(String pkgName) async {
    updated.add(pkgName);
    calls.add('update $pkgName');
  }

  @override
  Future<void> installExtensionFile(
    BuildContext context, {
    PlatformFile? file,
  }) async {
    // The real repository rejects a null pick before it mutates anything, so a
    // test that passed null would pass even if the file stopped being forwarded.
    if (file == null) throw Exception('no file picked');
    fileInstalls.add(file);
  }

  @override
  Future<List<Extension>?> getExtensionListStream() async => <Extension>[];
}
