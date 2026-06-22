// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../constants/gen/assets.gen.dart';
import '../../constants/navigation_bar_data.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';

class BigScreenNavigationBar extends StatelessWidget {
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
      BuildContext context, NavigationBarData data) {
    return NavigationRailDestination(
      icon: Icon(data.icon),
      label: Text(data.label(context)),
      selectedIcon: Icon(data.activeIcon),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The rail shows on any wide screen (width >= 600), which includes a phone
    // in landscape (short side < 600). There the height is tight, so drop the
    // app-icon header to make room for all destinations ("More" was falling off
    // the bottom). Real tablets keep the header.
    final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;

    final Widget leadingIcon;
    if (context.isDesktop) {
      leadingIcon = SizedBox(
        width: _extendedWidth,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => const AboutRoute().go(context),
              icon: ImageIcon(
                AssetImage(Assets.icons.darkIcon.path),
                size: 48,
              ),
              label: Text(context.l10n.appTitle),
              style: TextButton.styleFrom(
                foregroundColor: context.textTheme.bodyLarge?.color,
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),
      );
    } else {
      leadingIcon = IconButton(
        onPressed: () => const AboutRoute().go(context),
        icon: ImageIcon(
          AssetImage(Assets.icons.darkIcon.path),
          size: 48,
        ),
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
      extended: context.isDesktop,
      minExtendedWidth: _extendedWidth,
      labelType: context.isDesktop
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: isPhone ? null : leadingIcon,
      destinations: NavigationBarData.getNavList(context)
          .map<NavigationRailDestination>(
              (e) => getNavigationRailDestination(context, e))
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
