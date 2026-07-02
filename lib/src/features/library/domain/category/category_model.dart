// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
import '../../../../graphql/__generated__/schema.graphql.dart';
import './graphql/__generated__/fragment.graphql.dart';

typedef CategoryDto = Fragment$CategoryDto;

typedef CategoryCreate = Input$CreateCategoryInput;

typedef CategoryUpdate = Input$UpdateCategoryPatchInput;

/// Meta key marking a category hidden from the Library tab bar. Stored as a
/// per-category meta flag on the server so it's a property of the category
/// and syncs across devices.
const String kCategoryHiddenMetaKey = 'tsumiru.hidden';

extension CategoryHiddenX on CategoryDto {
  /// Whether this category is hidden from the Library tabs.
  bool get isHidden => meta.any(
        (m) => m.key == kCategoryHiddenMetaKey && m.value == 'true',
      );
}
