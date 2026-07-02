// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../controller/reader_preview_channel.dart';
import '../../../controller/reader_settings_model.dart';

int _argbChannel(int argb, int shift) => (argb >> shift) & 0xFF;

int _withArgbChannel(int argb, int shift, int value) =>
    (argb & ~(0xFF << shift)) | (value << shift);

/// Moving a colour channel (R/G/B, shift ≠ 24) while Alpha is 0 would be
/// invisible — the colour is fully transparent. Bump Alpha to full so the tint
/// shows immediately; the user can then dial Alpha back for subtlety.
int _ensureVisibleAlpha(int argb, int shift) =>
    (shift != 24 && _argbChannel(argb, 24) == 0)
        ? _withArgbChannel(argb, 24, 255)
        : argb;

/// Komikku-parity Custom-filter tab (ColorFilterPage): custom brightness,
/// RGBA color filter + blend mode, grayscale, inverted colors. Sliders
/// live-preview through the channels in reader_preview_channel.dart and
/// commit on onChangeEnd.
class CustomFilterTab extends ConsumerWidget {
  const CustomFilterTab({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);

    // I7: own scroll view; never the sheet's controller.
    return ListView(
      primary: false,
      children: [
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.customBrightness),
          value: settings.customBrightness,
          onChanged: model.setCustomBrightness,
        ),
        if (settings.customBrightness)
          _PreviewSlider(
            title: context.l10n.customBrightness,
            min: -75,
            max: 100,
            channel: readerBrightnessPreview,
            valueOf: (draft) => draft ?? settings.customBrightnessValue,
            onDrag: (v) => readerBrightnessPreview.value = v,
            onCommit: (v) {
              model.setCustomBrightnessValue(v);
              readerBrightnessPreview.value = null;
            },
          ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.customColorFilter),
          value: settings.customColorFilter,
          onChanged: model.setCustomColorFilter,
        ),
        if (settings.customColorFilter) ...[
          // Komikku slider order R/G/B/A over one packed ARGB pref.
          for (final (title, shift) in [
            (context.l10n.colorFilterRed, 16),
            (context.l10n.colorFilterGreen, 8),
            (context.l10n.colorFilterBlue, 0),
            (context.l10n.colorFilterAlpha, 24),
          ])
            _PreviewSlider(
              title: title,
              min: 0,
              max: 255,
              channel: readerColorFilterPreview,
              valueOf: (draft) =>
                  _argbChannel(draft ?? settings.colorFilterValue, shift),
              onDrag: (v) => readerColorFilterPreview.value = _ensureVisibleAlpha(
                _withArgbChannel(
                  readerColorFilterPreview.value ?? settings.colorFilterValue,
                  shift,
                  v,
                ),
                shift,
              ),
              onCommit: (v) {
                model.setColorFilterValue(_ensureVisibleAlpha(
                  _withArgbChannel(
                    readerColorFilterPreview.value ?? settings.colorFilterValue,
                    shift,
                    v,
                  ),
                  shift,
                ));
                readerColorFilterPreview.value = null;
              },
            ),
          _SectionLabel(context.l10n.colorFilterBlendMode),
          _ChipRow(
            children: [
              for (final mode in ColorFilterBlendMode.values)
                FilterChip(
                  selected: settings.colorFilterBlendMode == mode,
                  showCheckmark: false,
                  label: Text(mode.toLocale(context)),
                  onSelected: (_) => model.setColorFilterBlendMode(mode),
                ),
            ],
          ),
        ],
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.grayscale),
          value: settings.grayscale,
          onChanged: model.setGrayscale,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.invertedColors),
          value: settings.invertedColors,
          onChanged: model.setInvertedColors,
        ),
      ],
    );
  }
}

/// Live-preview slider: onChanged writes ONLY the preview channel (the overlay
/// repaints; no riverpod write, no tab/viewer rebuild); onChangeEnd commits.
/// The ValueListenableBuilder keeps the thumb tracking the draft.
class _PreviewSlider extends StatelessWidget {
  const _PreviewSlider({
    required this.title,
    required this.min,
    required this.max,
    required this.channel,
    required this.valueOf,
    required this.onDrag,
    required this.onCommit,
  });

  final String title;
  final int min;
  final int max;
  final ValueNotifier<int?> channel;
  final int Function(int? draft) valueOf;
  final ValueChanged<int> onDrag;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: channel,
      builder: (context, draft, _) {
        final value = valueOf(draft);
        return ListTile(
          title: Text(title),
          subtitle: Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  label: '$value',
                  onChanged: (v) => onDrag(v.round()),
                  onChangeEnd: (v) => onCommit(v.round()),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('$value', textAlign: TextAlign.end),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: context.theme.textTheme.labelLarge?.copyWith(
            color: context.theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Single-select chip row, Komikku SettingsChipRow feel.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: children,
      ),
    );
  }
}
