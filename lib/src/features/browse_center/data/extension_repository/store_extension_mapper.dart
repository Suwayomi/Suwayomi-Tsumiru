// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../domain/extension/graphql/__generated__/fragment.graphql.dart';
import '../../domain/extension/graphql/__generated__/store_fragment.graphql.dart';

/// Builds the legacy DTO every downstream consumer already understands
/// (same hand-construction precedent as offline_dto_mappers.dart).
Fragment$ExtensionDto extensionFromStoreDto(Fragment$StoreExtensionDto d) =>
    Fragment$ExtensionDto(
      apkName: d.apkName,
      hasUpdate: d.hasUpdate,
      iconUrl: d.iconUrl,
      isInstalled: d.isInstalled,
      contentWarning: d.contentWarning,
      isObsolete: d.isObsolete,
      lang: d.lang,
      name: d.name,
      pkgName: d.pkgName,
      repo: null,
      versionCode: d.versionCode,
      versionName: d.versionName,
    );
