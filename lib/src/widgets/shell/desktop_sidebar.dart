// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import '../../features/offline/data/offline_nav_status.dart';
import '../../features/settings/presentation/incognito/incognito_mode.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import '../../utils/platform/platform_runtime.dart';
import '../desktop/desktop_brand.dart';
import '../desktop/desktop_top_bar.dart';
import 'animated_nav_icon.dart';
import 'nav_badges.dart';
import 'sidebar_expanded.dart';

/// Whether the sidebar shows expanded rows at this window size class:
/// below [WindowSizeClass.large] it shows collapsed whatever the user chose,
/// and returns to their choice at large and above. The saved preference
/// itself never changes.
bool sidebarIsExpanded(BuildContext context, bool preference) =>
    preference && context.windowSizeClass >= WindowSizeClass.large;

/// Wide-desktop-only navigation sidebar (shown when [usesDesktopShell]).
///
/// Expanded (208 px): 40 px rows with icon + label and 2 px gaps. Collapsed
/// (60 px, 80 px on macOS so the traffic lights fit above the column): 44 px
/// icon-only rows with 6 px gaps, the label as a hover [Tooltip]. After the
/// destinations a flexible gap pins the foot to the bottom: a divider, then
/// an Incognito row with a switch and a Settings row. Collapsed, the foot
/// shows the same two rows as icon-only buttons (the switch hides and the
/// Incognito icon reflects on/off). The logo header lives in the desktop top
/// bar above the sidebar, so the sidebar starts directly under the bar; on
/// macOS the header moves into the sidebar as its first row, since the
/// traffic lights take the bar's top-left corner.
/// Width animates over 200 ms unless reduced motion is requested.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
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
  static double widthFor({required bool expanded, bool? isMacOS}) {
    if (expanded) return expandedWidth;
    return (isMacOS ?? isMacOSRuntime) ? macCollapsedWidth : collapsedWidth;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    // Desktop dropped the More tab: the five destinations match the shell
    // branches one-to-one, so [selectedIndex] needs no translation.
    final navList = NavigationBarData.desktopNavList;

    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    // The traffic-lights inset exists only on native macOS; web and tablets
    // always use the logo column.
    final isMacOS = isDesktopPlatform && isMacOSRuntime;
    // The bar's top-left corner is free only while it shows as one row. In
    // the two-row fallback (narrow window, sidebar forced collapsed) the title
    // bar already carries the logo, so the sidebar starts with the nav rows.
    final showBrandRow = isMacOS && desktopTopBarShowsMergedRow(context, ref);
    void expand() => ref.read(sidebarExpandedProvider.notifier).update(true);
    void collapse() => ref.read(sidebarExpandedProvider.notifier).update(false);

    final cs = context.colorScheme;
    final selectedBg = cs.primary.withValues(alpha: 0.22);
    final hoverBg = cs.onSurface.withValues(alpha: 0.05);

    // The width animates between the two rest widths. The wide content (icon
    // + label rows) cannot lay out in a narrow bar, so the content follows
    // the live width and flips at the midpoint: every frame shows content
    // that fits its frame, and rest states always match the pref.
    //
    // Branch 5 (More) has no destination row: its settings pages light the
    // Settings foot row instead, so the selected index never shifts for the
    // remaining destinations. The phone-only /more/history keeps the
    // History row lit. Without a router above (widget tests) the branch
    // index alone decides.
    final path = GoRouter.maybeOf(context)?.state.uri.path ?? '';
    final onPhoneHistory = path == const HistoryRoute().location;
    bool isSettingsPath(String p) =>
        p.startsWith('${const MoreRoute().location}/') &&
        p != const HistoryRoute().location;
    final settingsSelected =
        (selectedIndex >= navList.length || isSettingsPath(path)) &&
        !onPhoneHistory;
    final destSelected = selectedIndex < navList.length
        ? selectedIndex
        : (onPhoneHistory ? 2 : -1);
    final incognito = ref.watch(incognitoModeProvider);
    void toggleIncognito() => ref.read(incognitoModeProvider.notifier).toggle();

    Widget shellRow({
      required bool showExpanded,
      required bool selected,
      required String label,
      required Widget icon,
      Widget? trailing,
      required VoidCallback onTap,
      required double gapBelow,
    }) {
      final rowHeight = showExpanded ? _rowHeight : _collapsedRowHeight;
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
                  ?trailing,
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
          onTap: onTap,
          child: rowBody,
        ),
      );
      return Padding(
        padding: EdgeInsets.only(bottom: gapBelow),
        child: showExpanded
            ? tappable
            : Tooltip(message: label, child: tappable),
      );
    }

    Widget row(int index, bool showExpanded) {
      final data = navList[index];
      final selected = index == destSelected;
      final label = data.label(context);
      final rowGap = showExpanded ? _rowGap : _collapsedRowGap;
      return shellRow(
        showExpanded: showExpanded,
        selected: selected,
        label: label,
        icon: IconTheme(
          data: IconThemeData(color: selected ? cs.primary : cs.onSurface),
          child: badgedNavIcon(
            AnimatedNavIcon(vector: data.animatedIcon, selected: selected),
            data,
            downloadsPaused,
            extensionUpdates,
          ),
        ),
        onTap: () => onDestinationSelected(index),
        gapBelow: index == navList.length - 1 ? 0 : rowGap,
      );
    }

    Widget incognitoRow(bool showExpanded) {
      final label = context.l10n.incognitoShort;
      final rowGap = showExpanded ? _rowGap : _collapsedRowGap;
      return shellRow(
        showExpanded: showExpanded,
        selected: false,
        label: label,
        icon: Icon(
          incognito ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: cs.onSurface,
        ),
        trailing: Switch(value: incognito, onChanged: (_) => toggleIncognito()),
        onTap: toggleIncognito,
        gapBelow: rowGap,
      );
    }

    Widget settingsRow(bool showExpanded) {
      final label = context.l10n.settings;
      return shellRow(
        showExpanded: showExpanded,
        selected: settingsSelected,
        label: label,
        icon: Icon(
          Icons.settings_outlined,
          color: settingsSelected ? cs.primary : cs.onSurface,
        ),
        // Same entry as the More screen's Settings row: a push opens the
        // settings window at >= 840 and the full page below.
        onTap: () => const SettingsRoute().push(context),
        gapBelow: 0,
      );
    }

    // The destinations scroll when a short window can't fit them, while the
    // foot stays pinned to the bottom. The foot lives outside the scroll
    // view, so it is always visible.
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: widthFor(expanded: expanded, isMacOS: isMacOS),
          end: widthFor(expanded: expanded, isMacOS: isMacOS),
        ),
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        builder: (context, width, _) {
          final showExpanded = width > (expandedWidth + collapsedWidth) / 2;
          final maxHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : null;
          final brandRows = [
            if (showBrandRow) ...[
              if (showExpanded)
                DesktopBrandRow(
                  onCollapse: collapse,
                  height: _rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                )
              else
                SizedBox(
                  height: _rowHeight,
                  child: Center(
                    child: DesktopBrandExpandButton(onExpand: expand),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ];
          final destinationRows = [
            for (var i = 0; i < navList.length; i++) row(i, showExpanded),
          ];
          final footDivider = Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          );
          return SizedBox(
            width: width,
            height: maxHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: cs.outlineVariant)),
              ),
              padding: const EdgeInsets.all(8),
              child: maxHeight == null
                  ? SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...brandRows,
                          ...destinationRows,
                          footDivider,
                          incognitoRow(showExpanded),
                          settingsRow(showExpanded),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...brandRows,
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: destinationRows,
                            ),
                          ),
                        ),
                        footDivider,
                        incognitoRow(showExpanded),
                        settingsRow(showExpanded),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
