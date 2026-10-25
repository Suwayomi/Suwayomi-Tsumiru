// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/freezed_converters/language_json_converter.dart';
import '../language/language_model.dart';
import 'graphql/__generated__/fragment.graphql.dart';

export '../../../../graphql/__generated__/schema.graphql.dart'
    show Enum$FetchSourceMangaType;

typedef SourceDto = Fragment$SourceDto;

typedef SourceType = Enum$FetchSourceMangaType;

/// Global WebUI-compatible key, with string "true"/"false" values and no device segment.
const kSourcePinnedMetaKey = 'webUI_isPinned';

/// Tsumiru hidden-source key, shared across devices with string "true"/"false" values.
const kSourceHiddenMetaKey = 'tsumiru_isHidden';

extension SourceExtensions on SourceDto {
  Language? get language => LanguageJsonConverter.fromJson(lang);

  bool get isPinned =>
      meta.any((m) => m.key == kSourcePinnedMetaKey && m.value == 'true');

  bool get isHidden =>
      meta.any((m) => m.key == kSourceHiddenMetaKey && m.value == 'true');
}

extension SourceMangaTypeExtension on SourceType {
  IconData get icon => switch (this) {
        SourceType.LATEST => FluentIcons.news_24_regular,
        SourceType.POPULAR => FluentIcons.heart_24_regular,
        SourceType.SEARCH => FluentIcons.filter_24_regular,
        SourceType.$unknown => throw UnimplementedError(),
      };

  IconData get selectedIcon => switch (this) {
        SourceType.LATEST => FluentIcons.news_24_regular,
        SourceType.POPULAR => FluentIcons.heart_24_regular,
        SourceType.SEARCH => FluentIcons.filter_24_regular,
        SourceType.$unknown => throw UnimplementedError(),
      };

  String toLocale(BuildContext context) => switch (this) {
        SourceType.LATEST => context.l10n.sourceTypeLatest,
        SourceType.POPULAR => context.l10n.sourceTypePopular,
        SourceType.SEARCH => context.l10n.sourceTypeFilter,
        SourceType.$unknown => throw UnimplementedError(),
      };
}
