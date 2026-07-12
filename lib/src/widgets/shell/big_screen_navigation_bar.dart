// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/gen/assets.gen.dart';
import '../../constants/navigation_bar_data.dart';
import '../../features/offline/data/offline_nav_status.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import 'sidebar_expanded.dart';

class BigScreenNavigationBar extends ConsumerWidget {
  const BigScreenNavigationBar(
      {super.key,
      required this.selectedIndex,
      required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Width of the extended rail. Set explicitly on the [NavigationRail] below
  /// AND used to size the [leading] so the header fills the rail and can
  /// left-align (the rail's Column centers a narrower leading child).
  static const double _extendedWidth = 256;

  NavigationRailDestination getNavigationRailDestination(
      BuildContext context, NavigationBarData data, bool downloadsPaused) {
    final badged = downloadsPaused && data.icon == Icons.download_outlined;
    return NavigationRailDestination(
      icon: badged ? Badge(child: Icon(data.icon)) : Icon(data.icon),
      label: Text(data.label(context)),
      selectedIcon:
          badged ? Badge(child: Icon(data.activeIcon)) : Icon(data.activeIcon),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    // The rail shows on any wide screen (width >= 600), which includes a phone
    // in landscape (short side < 600). There the height is tight, so drop the
    // app-icon header to make room for all destinations ("More" was falling off
    // the bottom). Real tablets keep the header.
    final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;

    final expanded = ref.watch(sidebarExpandedProvider).ifNull(true);
    // Collapse only applies to the desktop (extended) rail; the tablet rail is
    // already an icon rail.
    final showExtended = context.isDesktop && expanded;
    void toggleSidebar() =>
        ref.read(sidebarExpandedProvider.notifier).update(!expanded);

    final logoIcon = ImageIcon(AssetImage(Assets.icons.darkIcon.path), size: 48);

    final Widget leadingIcon;
    if (showExtended) {
      leadingIcon = SizedBox(
        width: _extendedWidth,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => const AboutRoute().go(context),
                    icon: logoIcon,
                    label: Text(
                      context.l10n.appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: context.textTheme.bodyLarge?.color,
                      alignment: Alignment.centerLeft,
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
        ),
      );
    } else if (context.isDesktop) {
      // Collapsed: the header is just the expand chevron (logo hidden to keep the
      // rail narrow). Toggle stays at the top, so it never jumps between states.
      leadingIcon = IconButton(
        icon: const Icon(Icons.chevron_right),
        tooltip: context.l10n.expandSidebar,
        onPressed: toggleSidebar,
      );
    } else {
      // Tablet / landscape phone: compact logo (no collapse — already an icon rail).
      leadingIcon = IconButton(
        onPressed: () => const AboutRoute().go(context),
        icon: logoIcon,
      );
    }

    // The rail doesn't scroll on its own, so in landscape (short height) its
    // destinations overflow the bottom. Let it scroll when it can't fit, while
    // still filling the height when there's room (so spacing/indicator look
    // right).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              useIndicator: true,
              elevation: 5,
      extended: showExtended,
      minExtendedWidth: _extendedWidth,
      // Extended shows labels beside icons; otherwise keep them UNDER the icons
      // (collapsed desktop + tablet) rather than dropping them.
      labelType: showExtended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: isPhone ? null : leadingIcon,
      destinations: NavigationBarData.getNavList(context)
          .map<NavigationRailDestination>(
              (e) => getNavigationRailDestination(context, e, downloadsPaused))
          .toList(),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
            ),
          ),
        ),
      ),
    );
  }
}
