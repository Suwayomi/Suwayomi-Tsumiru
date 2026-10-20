// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import '../../features/offline/data/offline_nav_status.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import '../../utils/platform/platform_runtime.dart';
import '../desktop/desktop_brand.dart';
import '../desktop/desktop_top_bar.dart';
import 'animated_nav_icon.dart';
import 'nav_badges.dart';
import 'sidebar_expanded.dart';

/// Whether the sidebar shows expanded rows at this window width: below 1200
/// px it shows collapsed whatever the user chose, and returns to their choice
/// at 1200 and above. The saved preference itself never changes.
bool sidebarIsExpanded(BuildContext context, bool preference) =>
    preference && MediaQuery.sizeOf(context).width >= 1200;

/// Wide-desktop-only navigation sidebar (shown when [BuildContext.isDesktop]).
///
/// Expanded (208 px): 40 px rows with icon + label and 2 px gaps. Collapsed
/// (60 px, 80 px on macOS so the traffic lights fit above the column): 44 px
/// icon-only rows with 6 px gaps, the label as a hover [Tooltip]. The logo
/// header lives in the desktop top bar above the sidebar, so the sidebar
/// starts directly under the bar; on macOS the header moves into the sidebar
/// as its first row, since the traffic lights take the bar's top-left corner.
/// Width animates over 200 ms unless reduced motion is requested.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int? selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const double expandedWidth = 208;
  static const double collapsedWidth = 60;

  /// Collapsed width on macOS, so the traffic-lights inset above still lines
  /// up with the column.
  static const double macCollapsedWidth = 80;

  static const double _rowHeight = 40;
  static const double _collapsedRowHeight = 44;
  static const double _rowGap = 2;
  static const double _collapsedRowGap = 6;

  /// The sidebar's width for this state. [expanded] is the effective state
  /// ([sidebarIsExpanded]), not the raw preference. [isMacOS] defaults to the
  /// test-overridable platform check.
  static double widthFor({
    required bool expanded,
    bool? isMacOS,
    required double windowWidth,
  }) {
    if (expanded && windowWidth >= 1200) return expandedWidth;
    return (isMacOS ?? isMacOSRuntime) ? macCollapsedWidth : collapsedWidth;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final navList = NavigationBarData.getNavList(context);

    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    // The traffic-lights inset exists only on native macOS; web and tablets
    // always use the logo column.
    final isMacOS = isDesktopPlatform && isMacOSRuntime;
    // The bar's top-left corner is free only while it shows as one row. In
    // the two-row fallback (narrow window, sidebar forced collapsed) the title
    // bar already carries the logo, so the sidebar starts with the nav rows.
    final showBrandRow = isMacOS && desktopTopBarShowsMergedRow(context, ref);
    final windowWidth = MediaQuery.sizeOf(context).width;
    void expand() => ref.read(sidebarExpandedProvider.notifier).update(true);
    void collapse() =>
        ref.read(sidebarExpandedProvider.notifier).update(false);

    final cs = context.colorScheme;
    final selectedBg = cs.primary.withValues(alpha: 0.22);
    final hoverBg = cs.onSurface.withValues(alpha: 0.05);

    // The width animates between the two rest widths. The wide content (icon
    // + label rows) cannot lay out in a narrow bar, so the content follows
    // the live width and flips at the midpoint: every frame shows content
    // that fits its frame, and rest states always match the pref.
    Widget row(int index, bool showExpanded) {
      final data = navList[index];
      final selected = index == selectedIndex;
      final label = data.label(context);
      final iconColor = selected ? cs.primary : cs.onSurface;
      final icon = IconTheme(
        data: IconThemeData(color: iconColor),
        child: badgedNavIcon(
          AnimatedNavIcon(vector: data.animatedIcon, selected: selected),
          data,
          downloadsPaused,
          extensionUpdates,
        ),
      );
      final rowHeight = showExpanded ? _rowHeight : _collapsedRowHeight;
      final rowGap = showExpanded ? _rowGap : _collapsedRowGap;
      final rowBody = Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: selected ? selectedBg : null,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: showExpanded
            ? const EdgeInsets.symmetric(horizontal: 12)
            : EdgeInsets.zero,
        alignment: Alignment.center,
        child: showExpanded
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : icon,
      );
      final tappable = Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverBg,
          onTap: () => onDestinationSelected(index),
          child: rowBody,
        ),
      );
      return Padding(
        padding: EdgeInsets.only(
          bottom: index == navList.length - 1 ? 0 : rowGap,
        ),
        child: showExpanded
            ? tappable
            : Tooltip(message: label, child: tappable),
      );
    }

    // The sidebar doesn't scroll on its own, so in a short window its rows
    // would overflow the bottom. Let it scroll when it can't fit, while still
    // filling the height when there's room.
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: widthFor(
            expanded: expanded,
            isMacOS: isMacOS,
            windowWidth: windowWidth,
          ),
          end: widthFor(
            expanded: expanded,
            isMacOS: isMacOS,
            windowWidth: windowWidth,
          ),
        ),
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        builder: (context, width, _) {
          final showExpanded = width > (expandedWidth + collapsedWidth) / 2;
          final maxHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null;
          return SizedBox(
            width: width,
            height: maxHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: ((maxHeight ?? 0) - 16).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showBrandRow) ...[
                          if (showExpanded)
                            DesktopBrandRow(
                              onCollapse: collapse,
                              height: _rowHeight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            )
                          else
                            SizedBox(
                              height: _rowHeight,
                              child: Center(
                                child: DesktopBrandExpandButton(
                                  onExpand: expand,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                        for (var i = 0; i < navList.length; i++)
                          row(i, showExpanded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
