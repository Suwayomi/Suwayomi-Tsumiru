// Copyright (c) 2022 Contributors to the Suwayomi project
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
import '../tsumiru_logo.dart';
import 'animated_nav_icon.dart';
import 'desktop_sidebar.dart';
import 'nav_badges.dart';

class BigScreenNavigationBar extends ConsumerWidget {
  const BigScreenNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  NavigationRailDestination getNavigationRailDestination(
    BuildContext context,
    NavigationBarData data,
    bool selected,
    bool downloadsPaused,
    int extensionUpdates,
  ) {
    final icon = AnimatedNavIcon(vector: data.animatedIcon, selected: selected);
    return NavigationRailDestination(
      icon: badgedNavIcon(icon, data, downloadsPaused, extensionUpdates),
      label: Text(data.label(context)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.usesDesktopShell) {
      return DesktopSidebar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      );
    }

    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final navList = NavigationBarData.getNavList(context);
    // Landscape phones omit the header to leave room for destinations.
    final isPhone = !context.usesDesktopShell;

    const logoIcon = TsumiruLogo(size: 48);

    final leadingIcon = IconButton(
      onPressed: () => const AboutRoute().push(context),
      icon: logoIcon,
    );

    // NavigationRail cannot scroll itself; allow short windows to scroll destinations.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              useIndicator: true,
              elevation: 5,
              extended: false,
              labelType: NavigationRailLabelType.all,
              leading: isPhone ? null : leadingIcon,
              destinations: [
                for (var i = 0; i < navList.length; i++)
                  getNavigationRailDestination(
                    context,
                    navList[i],
                    i == selectedIndex,
                    downloadsPaused,
                    extensionUpdates,
                  ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
            ),
          ),
        ),
      ),
    );
  }
}
