// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_zoom_toggles.g.dart';

// Global zoom-gesture prefs (Komikku parity — zoom toggles are never
// per-series). Pinch-to-zoom lives in reader_pinch_to_zoom.dart.

@riverpod
class DoubleTapToZoom extends _$DoubleTapToZoom
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.doubleTapToZoom);
}

@riverpod
class DisableZoomOut extends _$DisableZoomOut
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.disableZoomOut);
}

@riverpod
class DisableZoomIn extends _$DisableZoomIn
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.disableZoomIn);
}
