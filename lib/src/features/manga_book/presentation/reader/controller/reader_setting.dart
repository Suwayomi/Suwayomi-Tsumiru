// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../../../domain/manga/manga_model.dart';

enum ReaderSettingScope { global, perSeries }

/// Per-series values override global settings; otherwise use the declared default.
@immutable
class ReaderSetting<T extends Object> {
  const ReaderSetting({
    required this.scope,
    required this.fallback,
    this.perSeriesKey,
    this.global,
  });

  final ReaderSettingScope scope;

  /// Per-series manga-meta key; null when the setting has no per-series path.
  final MangaMetaKeys? perSeriesKey;

  /// Null for sentinel-backed settings whose default is resolved by the engine.
  final ProviderListenable<T?>? global;

  final T fallback;

  T resolve(T? perSeries, T? global) => perSeries ?? global ?? fallback;

  T resolveWith(Ref ref, T? perSeries) =>
      resolve(perSeries, global == null ? null : ref.watch(global!));
}
