// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../domain/manga/manga_model.dart';
import '../../manga_details/controller/manga_details_controller.dart';
import 'reader_setting.dart';

part 'reader_settings_model.freezed.dart';
part 'reader_settings_model.g.dart';

/// Descriptor table mirroring exactly how each option persists today.
abstract final class ReaderSettings {
  /// Meta ?? sentinel: the app-wide default mode is dereferenced later by the
  /// engine — folding it in here would make "Default" unrepresentable.
  static const mode = ReaderSetting<ReaderMode>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerMode,
    fallback: ReaderMode.defaultReader,
  );

  static const navigationLayout = ReaderSetting<ReaderNavigationLayout>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerNavigationLayout,
    fallback: ReaderNavigationLayout.defaultNavigation,
  );

  static final sidePadding = ReaderSetting<double>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerPadding,
    global: readerPaddingKeyProvider,
    fallback: DBKeys.readerPadding.initial as double,
  );

  static final magnifierSize = ReaderSetting<double>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerMagnifierSize,
    global: readerMagnifierSizeKeyProvider,
    fallback: DBKeys.readerMagnifierSize.initial as double,
  );

  /// Global-only today: the reader never reads the per-series invert meta.
  static final invertTap = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: invertTapProvider,
    fallback: DBKeys.invertTap.initial as bool,
  );
}

@freezed
class ReaderSettingsState with _$ReaderSettingsState {
  const factory ReaderSettingsState({
    required ReaderMode readerMode,
    required ReaderNavigationLayout navigationLayout,
    required double sidePadding,
    required double magnifierSize,
    required bool invertTap,
  }) = _ReaderSettingsState;
}

/// Effective reader settings for one manga, seeded `perSeries ?? global` from
/// the existing providers/meta — the state home for the settings sheet.
@riverpod
class ReaderSettingsModel extends _$ReaderSettingsModel {
  @override
  ReaderSettingsState build(int mangaId) {
    final meta =
        ref.watch(mangaWithIdProvider(mangaId: mangaId)).valueOrNull?.metaData;
    return ReaderSettingsState(
      readerMode: ReaderSettings.mode.resolveWith(ref, meta?.readerMode),
      navigationLayout: ReaderSettings.navigationLayout
          .resolveWith(ref, meta?.readerNavigationLayout),
      sidePadding:
          ReaderSettings.sidePadding.resolveWith(ref, meta?.readerPadding),
      magnifierSize: ReaderSettings.magnifierSize
          .resolveWith(ref, meta?.readerMagnifierSize),
      invertTap: ReaderSettings.invertTap.resolveWith(ref, null),
    );
  }
}

/// Plan-named alias for the resolved-settings family.
final readerEffectiveSettingsProvider = readerSettingsModelProvider;
