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

/// Exact count, plain accent chip, or hidden. Supersedes the `unreadBadge`
/// bool, whose key is abandoned rather than migrated.
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

/// Source badge, including Local Source (a folder glyph). Supersedes the
/// separate `localBadge` switch.
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

/// Library grid cover geometry. Lives here, not in the library controller, so
/// `lib/src/widgets` cover tiles can read it without importing a feature.
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

/// The user's badge drag-order, as [LibraryBadge.id]s.
@riverpod
class BadgeOrder extends _$BadgeOrder
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.badgeOrder);
}

/// The [LibraryBadge.id]s pinned to a cover's top-RIGHT corner. Anything absent
/// clusters top-left.
@riverpod
class BadgeRightSide extends _$BadgeRightSide
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.badgeRightSide);
}

typedef BadgePlacement = ({LibraryBadge badge, BadgeSide side});

/// Every badge in the user's drag-order, tagged with the corner it belongs to.
///
/// Unknown persisted ids are dropped, and badges the saved order never
/// mentioned are appended in declaration order — so a newly shipped badge lands
/// at the end of an existing layout instead of vanishing.
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
