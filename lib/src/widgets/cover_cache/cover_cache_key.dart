// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Separates a cover's cache key from its server version.
const coverVersionMarker = '#cover-';

/// A changed server cover gets a new key and downloads; an unchanged one keeps its key.
String withCoverVersion(String key, String? coverVersion) =>
    (coverVersion == null || coverVersion.isEmpty)
    ? key
    : '$key$coverVersionMarker$coverVersion';

/// Prefix that keeps one ui-login account's images apart from another's.
String accountImageKeyPrefix(String catalogId) =>
    'tsumiru-image:account:${Uri.encodeComponent(catalogId)}/';

/// The key without its version, shared by every version of the same cover; null when unversioned.
String? unversionedCoverKey(String key) {
  final marker = key.lastIndexOf(coverVersionMarker);
  return marker < 0 ? null : key.substring(0, marker);
}
