// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'manga_cover_providers.g.dart';

@riverpod
class DownloadedBadge extends _$DownloadedBadge
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.downloadedBadge);
}

@riverpod
class OnDeviceBadge extends _$OnDeviceBadge
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.onDeviceBadge);
}

@riverpod
class UnreadBadgeStyle extends _$UnreadBadgeStyle
    with SharedPreferenceEnumClientMixin<UnreadBadgeMode> {
  @override
  UnreadBadgeMode? build() =>
      initialize(DBKeys.unreadBadgeMode, enumList: UnreadBadgeMode.values);
}

@riverpod
class ReadProgressBar extends _$ReadProgressBar
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.readProgressBar);
}

@riverpod
class ShowContinueReadingButton extends _$ShowContinueReadingButton
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showContinueReadingButton);
}

@riverpod
class LanguageBadge extends _$LanguageBadge
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.languageBadge);
}

@riverpod
class SourceBadge extends _$SourceBadge with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.sourceBadge);
}

@riverpod
class OutlineOnCovers extends _$OutlineOnCovers
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.outlineOnCovers);
}

@riverpod
class LibraryGridStyleKey extends _$LibraryGridStyleKey
    with SharedPreferenceEnumClientMixin<LibraryGridStyle> {
  @override
  LibraryGridStyle? build() =>
      initialize(DBKeys.libraryGridStyle, enumList: LibraryGridStyle.values);
}

@riverpod
class LimitTitleLines extends _$LimitTitleLines
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.limitTitleLines);
}

@riverpod
class BadgeOrder extends _$BadgeOrder
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.badgeOrder);
}

/// Physical top-right badge ids; absent ids cluster top-left.
@riverpod
class BadgeRightSide extends _$BadgeRightSide
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.badgeRightSide);
}

typedef BadgePlacement = ({LibraryBadge badge, BadgeSide side});

/// Drop unknown ids and append newly introduced badges in declaration order.
@riverpod
List<BadgePlacement> libraryBadgeLayout(Ref ref) {
  final savedOrder = ref.watch(badgeOrderProvider) ?? const <String>[];
  final rightIds = (ref.watch(badgeRightSideProvider) ??
          DBKeys.badgeRightSide.initial as List<String>)
      .toSet();

  final ordered = <LibraryBadge>[
    for (final id in savedOrder) ?LibraryBadge.fromId(id),
  ];
  for (final badge in LibraryBadge.values) {
    if (!ordered.contains(badge)) ordered.add(badge);
  }

  return [
    for (final badge in ordered)
      (
        badge: badge,
        side: rightIds.contains(badge.id) ? BadgeSide.right : BadgeSide.left,
      ),
  ];
}
