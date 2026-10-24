// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/category/category_model.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';

/// A null count hides the count.
typedef StripTab = ({String name, int? count});

const double _kStripHeight = 44;
const double _kTabHPadding = 12;
const double _kTabGap = 2;
const double _kUnderlineHeight = 3;
const double _kMoreFontSize = 13;

/// Overflow selection stays in More without reshuffling visible tabs; uses DefaultTabController.
class CategoryTabStrip extends HookWidget implements PreferredSizeWidget {
  const CategoryTabStrip({super.key, required this.tabs});

  final List<StripTab> tabs;

  @override
  Size get preferredSize => const Size.fromHeight(_kStripHeight);

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    useListenable(controller);
    if (tabs.isEmpty) return const SizedBox.shrink();
    final selected = controller.index.clamp(0, tabs.length - 1);
    final scheme = Theme.of(context).colorScheme;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    final moreLabel = context.l10n.more;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _computeLayout(
          maxWidth: constraints.maxWidth,
          tabs: tabs,
          selected: selected,
          direction: direction,
          scaler: scaler,
          moreLabel: moreLabel,
          nameStyle: _nameStyle(context, true),
          countStyle: _countStyle(context, true),
          moreStyle: _moreStyle(context, false),
          moreSelectedStyle: _nameStyle(
            context,
            true,
          ).copyWith(fontSize: _kMoreFontSize),
          moreSelectedCountStyle: _countStyle(
            context,
            true,
          ).copyWith(fontSize: _kMoreFontSize),
        );
        return Container(
          height: _kStripHeight,
          padding: const EdgeInsets.symmetric(horizontal: _kTabHPadding),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in layout.visible)
                _StripTabButton(
                  tab: tabs[i],
                  selected: i == selected,
                  textWidth: layout.textWidths[i],
                  onTap: () => controller.animateTo(i),
                ),
              if (layout.hidden.isNotEmpty) ...[
                if (layout.visible.isNotEmpty)
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 11,
                    ),
                    color: scheme.outlineVariant,
                  ),
                _MoreControl(
                  tabs: tabs,
                  hidden: layout.hidden,
                  selected: selected,
                  maxWidth: layout.moreMaxWidth,
                  moreLabel: moreLabel,
                  onPick: (i) => controller.animateTo(i),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

TextStyle _nameStyle(BuildContext context, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.titleSmall;
  return (base ?? const TextStyle(fontSize: 14)).copyWith(
    color: selected ? scheme.primary : scheme.onSurfaceVariant,
    fontWeight: selected ? FontWeight.w600 : null,
  );
}

TextStyle _countStyle(BuildContext context, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.titleSmall;
  return (base ?? const TextStyle(fontSize: 14)).copyWith(
    color: scheme.onSurfaceVariant.withValues(alpha: selected ? 0.8 : 0.7),
  );
}

TextStyle _moreStyle(BuildContext context, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.titleSmall;
  return (base ?? const TextStyle(fontSize: 14)).copyWith(
    fontSize: _kMoreFontSize,
    color: selected
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.75),
    fontWeight: selected ? FontWeight.w600 : null,
  );
}

double _textWidth(
  String text,
  TextStyle style,
  TextDirection direction,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

double _richWidth(
  StripTab tab,
  TextStyle name,
  TextStyle count,
  TextDirection direction,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: TextSpan(
      children: [
        TextSpan(text: tab.name, style: name),
        if (tab.count != null) TextSpan(text: ' (${tab.count})', style: count),
      ],
    ),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  return painter.width;
}

({
  List<int> visible,
  List<int> hidden,
  List<double> textWidths,
  double moreMaxWidth,
})
_computeLayout({
  required double maxWidth,
  required List<StripTab> tabs,
  required int selected,
  required TextDirection direction,
  required TextScaler scaler,
  required String moreLabel,
  required TextStyle nameStyle,
  required TextStyle countStyle,
  required TextStyle moreStyle,
  required TextStyle moreSelectedStyle,
  required TextStyle moreSelectedCountStyle,
}) {
  // Measure selected-style widths so changing selection cannot overflow the row.
  final textWidths = [
    for (final tab in tabs)
      _richWidth(tab, nameStyle, countStyle, direction, scaler),
  ];
  final tabWidths = [for (final w in textWidths) w + _kTabHPadding * 2];
  const dividerWidth = 1 + 16;
  const moreChrome = 8 + 20 + _kTabHPadding * 2; // gap + ▾ + padding
  String moreCountLabel(int n) => '$moreLabel ($n)';
  double moreCountWidth(int n) =>
      _textWidth(moreCountLabel(n), moreStyle, direction, scaler) + moreChrome;

  final avail = maxWidth - _kTabHPadding * 2;
  double total = 0;
  for (var i = 0; i < tabWidths.length; i++) {
    total += tabWidths[i] + (i == 0 ? 0 : _kTabGap);
  }
  if (total <= avail) {
    return (
      visible: [for (var i = 0; i < tabs.length; i++) i],
      hidden: const [],
      textWidths: textWidths,
      moreMaxWidth: double.infinity,
    );
  }

  // Reserve the widest possible More label, capped at 200 px, so selection never reshuffles tabs.
  var widestName = 0.0;
  for (final tab in tabs) {
    widestName = max(
      widestName,
      _richWidth(
        tab,
        moreSelectedStyle,
        moreSelectedCountStyle,
        direction,
        scaler,
      ),
    );
  }
  widestName = min(widestName, 200);
  final reserve =
      dividerWidth + max(moreCountWidth(tabs.length), widestName + moreChrome);

  final visible = <int>[];
  var used = 0.0;
  final hidden = <int>[];
  for (var i = 0; i < tabs.length; i++) {
    final need = tabWidths[i] + (visible.isEmpty ? 0 : _kTabGap);
    if (hidden.isEmpty && used + need <= avail - reserve) {
      visible.add(i);
      used += need;
    } else {
      hidden.add(i);
    }
  }
  // If one tab plus More cannot fit, show only More with an ellipsized label.
  final moreMaxWidth = max(64.0, avail - used - dividerWidth - moreChrome);
  return (
    visible: visible,
    hidden: hidden,
    textWidths: textWidths,
    moreMaxWidth: moreMaxWidth,
  );
}

class _StripTabButton extends StatelessWidget {
  const _StripTabButton({
    required this.tab,
    required this.selected,
    required this.textWidth,
    required this.onTap,
  });

  final StripTab tab;
  final bool selected;
  final double textWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kTabHPadding),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: tab.name,
                      style: _nameStyle(context, selected),
                    ),
                    if (tab.count != null)
                      TextSpan(
                        text: ' (${tab.count})',
                        style: _countStyle(context, selected),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Positioned(
                bottom: 0,
                child: Container(
                  width: textWidth,
                  height: _kUnderlineHeight,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(_kUnderlineHeight),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreControl extends StatelessWidget {
  const _MoreControl({
    required this.tabs,
    required this.hidden,
    required this.selected,
    required this.maxWidth,
    required this.moreLabel,
    required this.onPick,
  });

  final List<StripTab> tabs;
  final List<int> hidden;
  final int selected;
  final double maxWidth;
  final String moreLabel;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedHidden = hidden.contains(selected);
    final label = selectedHidden
        ? tabs[selected].name
        : '$moreLabel (${hidden.length})';
    final count = selectedHidden ? tabs[selected].count : null;
    final fullName = selectedHidden
        ? (count != null ? '${tabs[selected].name} ($count)' : label)
        : null;
    return MenuAnchor(
      menuChildren: [
        for (final i in hidden)
          MenuItemButton(
            onPressed: () => onPick(i),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: tabs[i].name),
                  if (tabs[i].count != null)
                    TextSpan(
                      text: ' (${tabs[i].count})',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => InkWell(
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kTabHPadding),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Tooltip(
                        message: fullName ?? '',
                        preferBelow: false,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: label,
                                style: _moreStyle(context, selectedHidden),
                              ),
                              if (count != null)
                                TextSpan(
                                  text: ' ($count)',
                                  style: _countStyle(
                                    context,
                                    selectedHidden,
                                  ).copyWith(fontSize: _kMoreFontSize),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_drop_down_rounded, size: 20),
                  ],
                ),
              ),
              if (selectedHidden)
                Positioned(
                  bottom: 0,
                  left: _kTabHPadding,
                  right: _kTabHPadding + 28,
                  child: Container(
                    height: _kUnderlineHeight,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(_kUnderlineHeight),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Counts come from the same filtered providers as the category bodies.
class DefaultCategoryTabStrip extends ConsumerWidget {
  const DefaultCategoryTabStrip({super.key, required this.categories});

  final List<CategoryDto> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCount = ref.watch(categoryNumberOfItemsProvider).ifNull(false);
    return CategoryTabStrip(
      tabs: [
        for (final category in categories)
          (
            name: category.name,
            count: showCount
                ? ref
                      .watch(
                        categoryMangaListWithQueryAndFilterProvider(
                          categoryId: category.id,
                        ),
                      )
                      .value
                      ?.length
                : null,
          ),
      ],
    );
  }
}

/// Counts come from the same filtered providers as the group bodies.
class GroupedCategoryTabStrip extends ConsumerWidget {
  const GroupedCategoryTabStrip({super.key, required this.groupedTabs});

  final List<GroupedTab> groupedTabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCount = ref.watch(categoryNumberOfItemsProvider).ifNull(false);
    return CategoryTabStrip(
      tabs: [
        for (final tab in groupedTabs)
          (
            name: tab.name,
            count: showCount
                ? ref
                      .watch(
                        groupedMangaListWithQueryAndFilterProvider(
                          tabId: tab.id,
                        ),
                      )
                      .value
                      ?.length
                : null,
          ),
      ],
    );
  }
}
