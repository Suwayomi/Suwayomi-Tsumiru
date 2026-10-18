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
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import '../tsumiru_logo.dart';
import 'animated_nav_icon.dart';
import 'nav_badges.dart';
import 'sidebar_expanded.dart';

/// Desktop-only navigation sidebar (shown when [BuildContext.isDesktop]).
///
/// Expanded (208 px): logo header with collapse chevron, then 40 px rows with
/// icon + label. Collapsed (60 px): centred logo (tap to expand), icon-only
/// rows with the label as a hover [Tooltip]. Width animates over 200 ms unless
/// reduced motion is requested.
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
  static const double _headerHeight = 56;
  static const double _rowHeight = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final navList = NavigationBarData.getNavList(context);

    final expanded = ref.watch(sidebarExpandedProvider).ifNull(true);
    void toggleSidebar() =>
        ref.read(sidebarExpandedProvider.notifier).update(!expanded);

    final cs = context.colorScheme;
    final selectedBg = cs.primary.withValues(alpha: 0.22);
    final hoverBg = cs.onSurface.withValues(alpha: 0.05);

    // The width animates between the two rest widths. The wide content (logo +
    // label header, icon + label rows) cannot lay out in a narrow bar, so the
    // content follows the live width and flips at the midpoint: every frame
    // shows content that fits its frame, and rest states always match the pref.
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
      final rowBody = Container(
        height: _rowHeight,
        decoration: BoxDecoration(
          color: selected ? selectedBg : null,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: showExpanded
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(
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
        padding: EdgeInsets.only(bottom: index == navList.length - 1 ? 0 : 2),
        child: showExpanded
            ? tappable
            : Tooltip(message: label, child: tappable),
      );
    }

    Widget header(bool showExpanded) => SizedBox(
      height: _headerHeight,
      child: showExpanded
          ? Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => const AboutRoute().push(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const TsumiruLogo(size: 32),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.l10n.appTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: context.l10n.collapseSidebar,
                    onPressed: toggleSidebar,
                  ),
                ],
              ),
            )
          : Center(
              child: IconButton(
                icon: const TsumiruLogo(size: 32),
                tooltip: context.l10n.expandSidebar,
                onPressed: toggleSidebar,
              ),
            ),
    );

    // The sidebar doesn't scroll on its own, so in a short window its rows
    // would overflow the bottom. Let it scroll when it can't fit, while still
    // filling the height when there's room.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: expanded ? expandedWidth : collapsedWidth,
                end: expanded ? expandedWidth : collapsedWidth,
              ),
              duration: context.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              builder: (context, width, _) {
                final showExpanded =
                    width > (expandedWidth + collapsedWidth) / 2;
                return SizedBox(
                  width: width,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header(showExpanded),
                        const SizedBox(height: 4),
                        for (var i = 0; i < navList.length; i++)
                          row(i, showExpanded),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
