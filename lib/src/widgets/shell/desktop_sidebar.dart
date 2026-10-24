// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import '../compact_switch.dart';
import '../desktop/desktop_brand.dart';
import '../desktop/desktop_top_bar.dart';
import 'nav_badges.dart';
import 'sidebar_expanded.dart';

/// Below large, collapse without changing the saved preference.
bool sidebarIsExpanded(BuildContext context, bool preference) =>
    preference && context.windowSizeClass >= WindowSizeClass.large;

/// Native macOS moves the brand row below its traffic lights; other platforms keep it in the top bar.
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

  /// Wider on macOS to align with the traffic-lights inset.
  static const double macCollapsedWidth = 80;

  static const double _rowHeight = 40;
  static const double _collapsedRowHeight = 44;
  static const double _rowGap = 2;
  static const double _collapsedRowGap = 6;

  /// expanded is the effective state; isMacOS defaults to the test-overridable check.
  static double widthFor({required bool expanded, bool? isMacOS}) {
    if (expanded) return expandedWidth;
    return (isMacOS ?? isMacOSRuntime) ? macCollapsedWidth : collapsedWidth;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final showFoot = context.windowSizeClass >= WindowSizeClass.expanded;
    final navList = showFoot
        ? NavigationBarData.desktopNavList
        : NavigationBarData.tabletNavList;

    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    final isMacOS = isDesktopPlatform && isMacOSRuntime;
    // Two-row mode already has a title-bar logo; only the merged macOS bar needs a sidebar brand.
    final showBrandRow = isMacOS && desktopTopBarShowsMergedRow(context, ref);
    void expand() => ref.read(sidebarExpandedProvider.notifier).update(true);
    void collapse() => ref.read(sidebarExpandedProvider.notifier).update(false);

    final cs = context.colorScheme;
    final selectedBg = cs.primary.withValues(alpha: 0.22);
    final hoverBg = cs.onSurface.withValues(alpha: 0.05);

    // Switch content at the animated width midpoint; keep Settings mapped to the hidden More branch.
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
            Icon(selected ? data.activeIcon : data.icon),
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
          incognito ? FluentIcons.incognito_24_filled : FluentIcons.incognito_24_regular,
          color: cs.onSurface,
        ),
        trailing: CompactSwitch(
          value: incognito,
          onChanged: (_) => toggleIncognito(),
        ),
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
          FluentIcons.settings_24_regular,
          color: settingsSelected ? cs.primary : cs.onSurface,
        ),
        onTap: () => const SettingsRoute().push(context),
        gapBelow: 0,
      );
    }

    // Scroll destinations separately so the footer remains visible in short windows.
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
                          if (showFoot) ...[
                            footDivider,
                            incognitoRow(showExpanded),
                            settingsRow(showExpanded),
                          ],
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
                        if (showFoot) ...[
                          footDivider,
                          incognitoRow(showExpanded),
                          settingsRow(showExpanded),
                        ],
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
