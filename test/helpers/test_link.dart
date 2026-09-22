// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

/// Windows' ERROR_PRIVILEGE_NOT_HELD: creating a real symlink needs admin
/// rights or Developer Mode.
const _privilegeNotHeld = 1314;

/// Creates a filesystem link at [path] pointing to [target] (a directory, or
/// a path that doesn't exist), for tests asserting that links are refused.
///
/// On Windows without the symlink privilege this falls back to a directory
/// junction (`mklink /J`, the same kind Scoop uses): it needs no privilege,
/// and Dart reports it as [FileSystemEntityType.link] with
/// `followLinks: false` — exactly what the production guards check — so the
/// test keeps its meaning instead of failing on setup.
Future<void> createTestLink(String path, String target) async {
  try {
    await Link(path).create(target);
  } on FileSystemException catch (e) {
    if (!_isWindowsPrivilegeError(e)) rethrow;
    _createJunction(path, target);
  }
}

/// Synchronous [createTestLink].
void createTestLinkSync(String path, String target) {
  try {
    Link(path).createSync(target);
  } on FileSystemException catch (e) {
    if (!_isWindowsPrivilegeError(e)) rethrow;
    _createJunction(path, target);
  }
}

bool _isWindowsPrivilegeError(FileSystemException e) =>
    Platform.isWindows && e.osError?.errorCode == _privilegeNotHeld;

void _createJunction(String path, String target) {
  // cmd reads a forward slash as an option switch.
  String native(String s) => s.replaceAll('/', r'\');
  final result = Process.runSync('cmd', [
    '/c',
    'mklink',
    '/J',
    native(path),
    native(target),
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Cannot create junction (mklink /J exited ${result.exitCode}): '
      '${result.stderr}',
      path,
    );
  }
}
