// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'reader_zoom_toggles.g.dart';


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

// Each viewer inherits its global preference until its own switch is set.

@riverpod
class PagedDoubleTapToZoom extends _$PagedDoubleTapToZoom
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.pagedDoubleTapToZoom,
        initial: ref.read(doubleTapToZoomProvider),
      );
}

@riverpod
class LongStripDoubleTapToZoom extends _$LongStripDoubleTapToZoom
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.longStripDoubleTapToZoom,
        initial: ref.read(doubleTapToZoomProvider),
      );
}

@riverpod
class PagedDisableZoomOut extends _$PagedDisableZoomOut
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.pagedDisableZoomOut,
        initial: ref.read(disableZoomOutProvider),
      );
}

@riverpod
class LongStripDisableZoomOut extends _$LongStripDisableZoomOut
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.longStripDisableZoomOut,
        initial: ref.read(disableZoomOutProvider),
      );
}
