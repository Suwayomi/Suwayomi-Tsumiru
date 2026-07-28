// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../reader_tap_invert/reader_tap_invert.dart';

part 'reader_navigation_layout_tile.g.dart';

/// Migration source for the two per-viewer keys below. Nothing reads this to
/// decide tap zones any more.
@riverpod
class ReaderNavigationLayoutKey extends _$ReaderNavigationLayoutKey
    with SharedPreferenceEnumClientMixin<ReaderNavigationLayout> {
  @override
  ReaderNavigationLayout? build() => initialize(
        DBKeys.readerNavigationLayout,
        enumList: ReaderNavigationLayout.values,
      );
}

// Komikku keeps tap zones per viewer (navigationModePager /
// navigationModeWebtoon), which is why they sit inside the Paged and Long
// strip groups rather than above them.

@riverpod
class PagedNavigationLayoutKey extends _$PagedNavigationLayoutKey
    with SharedPreferenceEnumClientMixin<ReaderNavigationLayout> {
  @override
  ReaderNavigationLayout? build() => initialize(
        DBKeys.pagedNavigationLayout,
        enumList: ReaderNavigationLayout.values,
        initial: ref.read(readerNavigationLayoutKeyProvider),
      );
}

@riverpod
class LongStripNavigationLayoutKey extends _$LongStripNavigationLayoutKey
    with SharedPreferenceEnumClientMixin<ReaderNavigationLayout> {
  @override
  ReaderNavigationLayout? build() => initialize(
        DBKeys.longStripNavigationLayout,
        enumList: ReaderNavigationLayout.values,
        initial: ref.read(readerNavigationLayoutKeyProvider),
      );
}

/// Tap zones for one viewer. Paged and long strip keep their own, so the tile
/// appears once in each viewer group rather than above both.
class ReaderNavigationLayoutTile extends ConsumerWidget {
  const ReaderNavigationLayoutTile({super.key, required this.longStrip});

  final bool longStrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = (longStrip
            ? ref.watch(longStripNavigationLayoutKeyProvider)
            : ref.watch(pagedNavigationLayoutKeyProvider)) ??
        ReaderNavigationLayout.defaultNavigation;
    void set(ReaderNavigationLayout? value) => longStrip
        ? ref.read(longStripNavigationLayoutKeyProvider.notifier).update(value)
        : ref.read(pagedNavigationLayoutKeyProvider.notifier).update(value);
    return ListTile(
      leading: const Icon(Icons.touch_app_rounded),
      subtitle: Text(layout.toLocale(context)),
      title: Text(context.l10n.readerNavigationLayout),
      onTap: () => showDialog(
        context: context,
        builder: (context) => RadioListPopup<ReaderNavigationLayout>(
          title: context.l10n.readerNavigationLayout,
          // Komikku's order, and it keeps Default now that Default resolves to
          // a real layout rather than meaning "off".
          optionList: ReaderNavigationLayout.displayOrder,
          getOptionTitle: (value) => value.toLocale(context),
          value: layout,
          onChange: (enumValue) async {
            set(enumValue);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

/// Four-value tap inversion for one viewer, matching Komikku's
/// pagerNavInverted / webtoonNavInverted. Settings previously offered only a
/// legacy on/off switch.
class ReaderTapInvertTile extends ConsumerWidget {
  const ReaderTapInvertTile({super.key, required this.longStrip});

  final bool longStrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invert = (longStrip
            ? ref.watch(longStripTapInvertKeyProvider)
            : ref.watch(pagedTapInvertKeyProvider)) ??
        TapInvert.none;
    void set(TapInvert? value) => longStrip
        ? ref.read(longStripTapInvertKeyProvider.notifier).update(value)
        : ref.read(pagedTapInvertKeyProvider.notifier).update(value);
    return ListTile(
      leading: const Icon(Icons.switch_left_rounded),
      subtitle: Text(invert.toLocale(context)),
      title: Text(context.l10n.readerNavigationLayoutInvert),
      onTap: () => showDialog(
        context: context,
        builder: (context) => RadioListPopup<TapInvert>(
          title: context.l10n.readerNavigationLayoutInvert,
          optionList: TapInvert.values,
          getOptionTitle: (value) => value.toLocale(context),
          value: invert,
          onChange: (enumValue) async {
            set(enumValue);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }
}
