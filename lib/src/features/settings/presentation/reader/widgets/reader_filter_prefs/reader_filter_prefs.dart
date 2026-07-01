// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_filter_prefs.g.dart';

// Global Custom-filter tab prefs (Komikku ColorFilterPage parity).

@riverpod
class CustomBrightness extends _$CustomBrightness
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.customBrightness);
}

/// -75..100. Negatives render the black dim overlay; positives are inert
/// (Komikku sets the Android window brightness attr — no plugin here).
@riverpod
class CustomBrightnessValue extends _$CustomBrightnessValue
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.customBrightnessValue);
}

@riverpod
class CustomColorFilter extends _$CustomColorFilter
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.customColorFilter);
}

/// Packed ARGB, like Komikku's color_filter_value.
@riverpod
class ColorFilterValue extends _$ColorFilterValue
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.colorFilterValue);
}

@riverpod
class ColorFilterBlendModeKey extends _$ColorFilterBlendModeKey
    with SharedPreferenceEnumClientMixin<ColorFilterBlendMode> {
  @override
  ColorFilterBlendMode? build() => initialize(
        DBKeys.colorFilterBlendMode,
        enumList: ColorFilterBlendMode.values,
      );
}

@riverpod
class Grayscale extends _$Grayscale with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.grayscale);
}

@riverpod
class InvertedColors extends _$InvertedColors
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.invertedColors);
}
