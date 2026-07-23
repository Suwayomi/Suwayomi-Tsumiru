// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:animated_vector/animated_vector.dart';
import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';
import 'animated_nav_vectors.dart';

class NavigationBarData {
  final String Function(BuildContext context) label;
  final IconData icon;
  final IconData activeIcon;
  final AnimatedVectorData animatedIcon;

  // Static list for phone/small screens (History under More)
  static final phoneNavList = [
    NavigationBarData(
      icon: Icons.collections_bookmark_outlined,
      activeIcon: Icons.collections_bookmark_rounded,
      animatedIcon: AnimatedNavVectors.library,
      label: (context) => context.l10n.library,
    ),
    NavigationBarData(
      icon: Icons.new_releases_outlined,
      activeIcon: Icons.new_releases_rounded,
      animatedIcon: AnimatedNavVectors.updates,
      label: (context) => context.l10n.updates,
    ),
    NavigationBarData(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      animatedIcon: AnimatedNavVectors.browse,
      label: (context) => context.l10n.browse,
    ),
    NavigationBarData(
      icon: Icons.download_outlined,
      activeIcon: Icons.download_rounded,
      animatedIcon: AnimatedNavVectors.downloads,
      label: (context) => context.l10n.downloads,
    ),
    NavigationBarData(
      icon: Icons.more_horiz_outlined,
      activeIcon: Icons.more_horiz_rounded,
      animatedIcon: AnimatedNavVectors.more,
      label: (context) => context.l10n.more,
    ),
  ];

  // Static list for tablet/large screens (History between Updates and Browse)
  static final tabletNavList = [
    NavigationBarData(
      icon: Icons.collections_bookmark_outlined,
      activeIcon: Icons.collections_bookmark_rounded,
      animatedIcon: AnimatedNavVectors.library,
      label: (context) => context.l10n.library,
    ),
    NavigationBarData(
      icon: Icons.new_releases_outlined,
      activeIcon: Icons.new_releases_rounded,
      animatedIcon: AnimatedNavVectors.updates,
      label: (context) => context.l10n.updates,
    ),
    NavigationBarData(
      icon: Icons.history_outlined,
      activeIcon: Icons.history_rounded,
      animatedIcon: AnimatedNavVectors.history,
      label: (context) => context.l10n.history,
    ),
    NavigationBarData(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      animatedIcon: AnimatedNavVectors.browse,
      label: (context) => context.l10n.browse,
    ),
    NavigationBarData(
      icon: Icons.download_outlined,
      activeIcon: Icons.download_rounded,
      animatedIcon: AnimatedNavVectors.downloads,
      label: (context) => context.l10n.downloads,
    ),
    NavigationBarData(
      icon: Icons.more_horiz_outlined,
      activeIcon: Icons.more_horiz_rounded,
      animatedIcon: AnimatedNavVectors.more,
      label: (context) => context.l10n.more,
    ),
  ];

  // Dynamic navigation list based on context
  static List<NavigationBarData> getNavList(BuildContext context) {
    return context.isTablet ? tabletNavList : phoneNavList;
  }

  // Legacy navList for backward compatibility - defaults to phone layout
  static final navList = phoneNavList;

  NavigationBarData({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.animatedIcon,
  });
}
