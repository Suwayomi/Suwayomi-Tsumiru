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
    // Desktop uses the custom sidebar (icon rows, no under-icon labels);
    // tablet and landscape phone keep the icon rail exactly as before.
    if (context.isDesktop) {
      return DesktopSidebar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      );
    }

    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final extensionUpdates =
        ref.watch(extensionUpdateBadgeCountProvider).value ?? 0;
    final navList = NavigationBarData.getNavList(context);
    // The rail shows on any wide screen (width >= 600), which includes a phone
    // in landscape (short side < 600). There the height is tight, so drop the
    // app-icon header to make room for all destinations ("More" was falling off
    // the bottom). Real tablets keep the header.
    final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;

    const logoIcon = TsumiruLogo(size: 48);

    // Tablet / landscape phone: compact logo (no collapse — already an icon rail).
    final leadingIcon = IconButton(
      onPressed: () => const AboutRoute().push(context),
      icon: logoIcon,
    );

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
