// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_general_prefs.g.dart';

/// Komikku MILLI_CONVERSION: flashDuration slider ticks → milliseconds.
const kFlashMsPerTick = 100;

// Global General-tab reader prefs (Komikku GeneralSettingsPage parity).

@riverpod
class ReaderBackgroundColorKey extends _$ReaderBackgroundColorKey
    with SharedPreferenceEnumClientMixin<ReaderBackgroundColor> {
  @override
  ReaderBackgroundColor? build() => initialize(
        DBKeys.readerBackgroundColor,
        enumList: ReaderBackgroundColor.values,
      );
}

/// Inert for now: no standalone page-number indicator exists outside the
/// seekbars (page_number_slider.dart is dead code).
@riverpod
class ShowPageNumber extends _$ShowPageNumber
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.showPageNumber);
}

@riverpod
class LandscapeVerticalSeekbar extends _$LandscapeVerticalSeekbar
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.landscapeVerticalSeekbar);
}

@riverpod
class ReaderFullscreen extends _$ReaderFullscreen
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.readerFullscreen);
}

@riverpod
class DrawUnderCutout extends _$DrawUnderCutout
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.drawUnderCutout);
}

/// Inert: the reader's long-press is the magnifier, not a page-actions sheet.
@riverpod
class ReadWithLongTap extends _$ReadWithLongTap
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.readWithLongTap);
}

/// Inert: transition pages live in the frozen webtoon engine.
@riverpod
class AlwaysShowChapterTransition extends _$AlwaysShowChapterTransition
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.alwaysShowChapterTransition);
}

@riverpod
class FlashOnPageChange extends _$FlashOnPageChange
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.flashOnPageChange);
}

/// Slider ticks 1..15, each 100 ms of flash.
@riverpod
class FlashDuration extends _$FlashDuration
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.flashDuration);
}

/// Flash every Nth page change, 1..10.
@riverpod
class FlashPageInterval extends _$FlashPageInterval
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.flashPageInterval);
}

@riverpod
class FlashColorKey extends _$FlashColorKey
    with SharedPreferenceEnumClientMixin<FlashColor> {
  @override
  FlashColor? build() =>
      initialize(DBKeys.flashColor, enumList: FlashColor.values);
}
