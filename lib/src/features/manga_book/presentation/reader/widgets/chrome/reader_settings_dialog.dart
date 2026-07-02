// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../controller/reader_preview_channel.dart';
import '../../controller/reader_settings_model.dart';
import 'tabs/custom_filter_tab.dart';
import 'tabs/general_tab.dart';
import 'tabs/reading_mode_tab.dart';

part 'reader_settings_dialog.g.dart';

typedef ReaderSettingsPreviewState = ({Color scrim, bool chromeHidden});

/// Live-preview state driven by the sheet's tab: the Custom-filter tab clears
/// the scrim and hides the chrome so the page shows.
@riverpod
class ReaderSettingsPreview extends _$ReaderSettingsPreview {
  static const ReaderSettingsPreviewState _shown =
      (scrim: Colors.black54, chromeHidden: false);
  static const ReaderSettingsPreviewState _pageVisible =
      (scrim: Colors.transparent, chromeHidden: true);

  @override
  ReaderSettingsPreviewState build() => _shown;

  void onTabChanged(int index) => state = index == 2 ? _pageVisible : _shown;
}

/// C2: the modal barrier stays a REAL gesture-blocking barrier on every tab;
/// only its color is remapped, so drags can never leak to the viewer below.
class _ReaderSettingsSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _ReaderSettingsSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
  }) : super(
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
        );

  Color _barrierColor = Colors.black54;

  @override
  Color get barrierColor => _barrierColor;

  set barrierColor(Color value) {
    if (value == _barrierColor) return;
    _barrierColor = value;
    changedInternalState();
  }
}

/// Opens the reader settings sheet and owns its full dismissal contract (C3):
/// one idempotent restore runs on every dismiss path via [Future.whenComplete].
Future<void> showReaderSettingsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required int mangaId,
  required ValueNotifier<bool> visibility,
  required ValueNotifier<double> readerPadding,
  required ValueNotifier<double> magnifierSize,
}) {
  final navigator = Navigator.of(context);
  final route = _ReaderSettingsSheetRoute<void>(
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => ReaderSettingsDialog(
      mangaId: mangaId,
      readerPadding: readerPadding,
      magnifierSize: magnifierSize,
    ),
  );

  final wasVisible = visibility.value;
  final subscription = ref.listenManual(
    readerSettingsPreviewProvider,
    (_, next) {
      route.barrierColor = next.scrim;
      visibility.value = next.chromeHidden ? false : wasVisible;
    },
  );

  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    subscription.close();
    // Flush any live slider draft the dismissal interrupted mid-drag (§2.4).
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    final brightnessDraft = readerBrightnessPreview.value;
    if (brightnessDraft != null) model.setCustomBrightnessValue(brightnessDraft);
    final colorDraft = readerColorFilterPreview.value;
    if (colorDraft != null) model.setColorFilterValue(colorDraft);
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
    visibility.value = wasVisible;
    ref.invalidate(readerSettingsPreviewProvider);
  }

  return navigator.push(route).whenComplete(dismiss);
}

/// 3-tab live-preview settings sheet replacing the reader's old side drawer.
class ReaderSettingsDialog extends HookConsumerWidget {
  const ReaderSettingsDialog({
    super.key,
    required this.mangaId,
    required this.readerPadding,
    required this.magnifierSize,
  });

  final int mangaId;

  /// The wrapper's live padding/magnifier notifiers — shared so slider drags
  /// keep updating the open reader immediately, exactly like the old drawer.
  final ValueNotifier<double> readerPadding;
  final ValueNotifier<double> magnifierSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(initialLength: 3);
    useEffect(() {
      void onTab() => ref
          .read(readerSettingsPreviewProvider.notifier)
          .onTabChanged(tabController.index);
      tabController.addListener(onTab);
      return () => tabController.removeListener(onTab);
    }, [tabController]);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      // I7: the sheet's scroll controller is deliberately attached to NOTHING —
      // sharing it across the tabs is a hard "attached to multiple scroll
      // views" crash. Each tab owns its own scroll view (primary: false).
      builder: (context, _) => Material(
        color: context.theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              controller: tabController,
              tabs: [
                Tab(text: context.l10n.readerMode),
                Tab(text: context.l10n.general),
                Tab(text: context.l10n.customFilter),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: tabController,
                children: [
                  ReadingModeTab(
                    mangaId: mangaId,
                    readerPadding: readerPadding,
                    magnifierSize: magnifierSize,
                  ),
                  GeneralTab(mangaId: mangaId),
                  CustomFilterTab(mangaId: mangaId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
