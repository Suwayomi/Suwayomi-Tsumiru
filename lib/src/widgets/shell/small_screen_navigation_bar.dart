// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/navigation_bar_data.dart';
import '../../features/offline/data/offline_nav_status.dart';
import 'animated_nav_icon.dart';

class SmallScreenNavigationBar extends ConsumerWidget {
  const SmallScreenNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final void Function(int) onDestinationSelected;

  NavigationDestination getNavigationDestination(BuildContext context,
      NavigationBarData data, bool selected, bool downloadsPaused) {
    final badged = downloadsPaused && data.icon == Icons.download_outlined;
    final icon = AnimatedNavIcon(vector: data.animatedIcon, selected: selected);
    return NavigationDestination(
      icon: badged ? Badge(child: icon) : icon,
      label: data.label(context),
      tooltip: data.label(context),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsPaused = ref.watch(downloadsPausedBadgeProvider);
    final navList = NavigationBarData.getNavList(context);
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(overflow: TextOverflow.ellipsis),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          for (var i = 0; i < navList.length; i++)
            getNavigationDestination(
                context, navList[i], i == selectedIndex, downloadsPaused),
        ],
      ),
    );
  }
}
