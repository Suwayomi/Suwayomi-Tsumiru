// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../controller/reader_settings_model.dart';

/// The old drawer's 4 options, wired through [ReaderSettingsModel]. The
/// mode/nav popups open as dialogs ON TOP of the sheet — the sheet never pops.
/// Task 9 replaces the ListTiles with Mihon chips.
class ReadingModeTab extends ConsumerWidget {
  const ReadingModeTab({
    super.key,
    required this.mangaId,
    required this.readerPadding,
    required this.magnifierSize,
  });

  final int mangaId;
  final ValueNotifier<double> readerPadding;
  final ValueNotifier<double> magnifierSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    // I7: own scroll view; never the sheet's controller.
    return ListView(
      primary: false,
      children: [
        ListTile(
          leading: const Icon(Icons.app_settings_alt_outlined),
          title: Text(context.l10n.readerMode),
          subtitle: Text(settings.readerMode.toLocale(context)),
          onTap: () => showDialog(
            context: context,
            builder: (dialogContext) => RadioListPopup<ReaderMode>(
              optionList: ReaderMode.values,
              value: settings.readerMode,
              title: context.l10n.readerMode,
              getOptionTitle: (value) => value.toLocale(context),
              onChange: (mode) {
                Navigator.pop(dialogContext);
                ref
                    .read(readerSettingsModelProvider(mangaId).notifier)
                    .setReaderMode(mode);
              },
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.touch_app_rounded),
          title: Text(context.l10n.readerNavigationLayout),
          subtitle: Text(settings.navigationLayout.toLocale(context)),
          onTap: () => showDialog(
            context: context,
            builder: (dialogContext) => RadioListPopup<ReaderNavigationLayout>(
              optionList: ReaderNavigationLayout.values,
              value: settings.navigationLayout,
              title: context.l10n.readerNavigationLayout,
              getOptionTitle: (value) => value.toLocale(context),
              onChange: (layout) {
                Navigator.pop(dialogContext);
                ref
                    .read(readerSettingsModelProvider(mangaId).notifier)
                    .setNavigationLayout(layout);
              },
            ),
          ),
        ),
        AsyncReaderPaddingSlider(
          readerPadding: readerPadding,
          onChanged: (value) => ref
              .read(readerSettingsModelProvider(mangaId).notifier)
              .setSidePadding(value),
        ),
        AsyncReaderMagnifierSizeSlider(
          readerMagnifierSize: magnifierSize,
          onChanged: (value) => ref
              .read(readerSettingsModelProvider(mangaId).notifier)
              .setMagnifierSize(value),
        ),
      ],
    );
  }
}
