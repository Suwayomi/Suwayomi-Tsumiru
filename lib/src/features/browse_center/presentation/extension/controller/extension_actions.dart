// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../data/extension_repository/extension_repository.dart';
import '../../source/controller/source_controller.dart';
import 'extension_controller.dart';

part 'extension_actions.g.dart';

/// The single entry point for installing, updating and uninstalling extensions.
///
/// The server registers an extension's sources in the same transaction that
/// installs it, so the source list is stale the moment the mutation returns.
/// Browse keeps its tabs alive, so a stale list survives every tab switch and
/// only clears on restart — route every extension action through here so the
/// source list can never be left behind again (#344).
class ExtensionActions {
  ExtensionActions(this._ref);

  final Ref _ref;

  ExtensionRepository get _repository => _ref.read(extensionRepositoryProvider);

  Future<void> install(String pkgName, {String? languageCode}) =>
      _refreshAfter((current) => _install(pkgName, languageCode, current));

  Future<void> reinstall(String pkgName, {String? languageCode}) =>
      _refreshAfter((current) async {
        final repository = _repository;
        repository.permissions.require(Enum$UserPermission.INSTALL_EXTENSIONS);
        repository.permissions.require(
          Enum$UserPermission.UNINSTALL_EXTENSIONS,
        );
        await repository.uninstallExtension(pkgName);
        if (!current()) return;
        await _install(pkgName, languageCode, current);
      });

  Future<void> installFile(BuildContext context, {PlatformFile? file}) =>
      _refreshAfter(
        (_) => _repository.installExtensionFile(context, file: file),
      );

  Future<void> update(String pkgName) =>
      _refreshAfter((_) => _repository.updateExtension(pkgName));

  Future<void> uninstall(String pkgName) =>
      _refreshAfter((_) => _repository.uninstallExtension(pkgName));

  Future<void> _install(
    String pkgName,
    String? languageCode,
    bool Function() current,
  ) async {
    await _repository.installExtension(pkgName);
    if (!current()) return;
    if (languageCode.isNotBlank) _enableSourceLanguage(languageCode!);
  }

  /// A blank filter means the user turned every language off (the key defaults
  /// to a populated list), so installing an extension doesn't switch one back on.
  void _enableSourceLanguage(String code) {
    final enabled = _ref.read(sourceLanguageFilterProvider);
    if (enabled.isNotBlank && !enabled!.contains(code)) {
      _ref
          .read(sourceLanguageFilterProvider.notifier)
          .update({...enabled, code}.toList());
    }
  }

  Future<void> _refreshAfter(
    Future<void> Function(bool Function()) mutate,
  ) async {
    final session = _ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    bool current() => _ref.mounted && session();
    if (!current()) return;
    await mutate(current);
    if (!current()) return;
    _ref.invalidate(sourceListProvider);
    return _ref.refresh(extensionProvider.future);
  }
}

/// Kept alive on purpose: callers reach it with `ref.read` inside a button
/// handler and then await a network round trip. An auto-disposing provider
/// would be gone before the refresh runs.
@Riverpod(keepAlive: true)
ExtensionActions extensionActions(Ref ref) => ExtensionActions(ref);
