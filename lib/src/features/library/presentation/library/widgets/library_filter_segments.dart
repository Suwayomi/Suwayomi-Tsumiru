// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Falls back to radio rows when any label cannot fit its equal-width segment.
class AdaptiveSegments<T> extends StatelessWidget {
  const AdaptiveSegments({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  static const _boxHeight = 40.0;
  static const _padding = EdgeInsets.all(4);
  static const _gap = 2.0;
  static const _labelPadding = 20.0;

  bool _fits(
    double maxWidth,
    TextStyle? style,
    TextDirection dir,
    TextScaler scaler,
  ) {
    if (!maxWidth.isFinite || options.isEmpty) return false;
    final gaps = _padding.horizontal + _gap * (options.length - 1);
    final segWidth = (maxWidth - gaps) / options.length;
    for (final option in options) {
      final painter = TextPainter(
        text: TextSpan(text: option.label, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > segWidth - _labelPadding) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final labelStyle = context.theme.textTheme.labelLarge;
    final dir = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_fits(constraints.maxWidth, labelStyle, dir, scaler)) {
          return RadioGroup<T>(
            groupValue: value,
            onChanged: (next) {
              // null selects Any when present; discard it only for tristate toggles without a null option.
              if (next != null ||
                  options.any((option) => option.value == null)) {
                onChanged(next as T);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  RadioListTile<T>(
                    value: option.value,
                    title: Text(option.label),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          );
        }
        return Container(
          height: _boxHeight,
          padding: _padding,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            spacing: _gap,
            children: [
              for (final option in options)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: option.value == value,
                    inMutuallyExclusiveGroup: true,
                    label: option.label,
                    excludeSemantics: true,
                    child: _Segment(
                      label: option.label,
                      selected: option.value == value,
                      onTap: () => onChanged(option.value),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return SizedBox(
      height: 32,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Any maps to null, first option to true, second to false.
class LibraryTriStateSegment extends ConsumerWidget {
  const LibraryTriStateSegment({
    super.key,
    required this.heading,
    required this.provider,
    required this.onChanged,
    this.includedLabel,
    this.excludedLabel,
  });

  final String heading;
  final ProviderListenable<bool?> provider;
  final ValueChanged<bool?> onChanged;
  final String? includedLabel;
  final String? excludedLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(heading),
        AdaptiveSegments<bool?>(
          value: current,
          onChanged: onChanged,
          options: [
            SegmentOption(value: null, label: context.l10n.filterStateAny),
            SegmentOption(
              value: true,
              label: includedLabel ?? context.l10n.yes,
            ),
            SegmentOption(
              value: false,
              label: excludedLabel ?? context.l10n.no,
            ),
          ],
        ),
      ],
    );
  }
}

class FilterSectionHeading extends StatelessWidget {
  const FilterSectionHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: context.theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
