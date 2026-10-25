// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// Which approved motion a destination icon plays on selection changes.
enum NavMotion { library, updates, history, browse, downloads, more }

class NavigationBarData {
  final String Function(BuildContext context) label;
  final IconData icon;
  final IconData activeIcon;
  final NavMotion motion;

  static final phoneNavList = [
    NavigationBarData(
      icon: FluentIcons.library_24_regular,
      activeIcon: FluentIcons.library_24_filled,
      motion: NavMotion.library,
      label: (context) => context.l10n.library,
    ),
    NavigationBarData(
      icon: FluentIcons.news_24_regular,
      activeIcon: FluentIcons.news_24_filled,
      motion: NavMotion.updates,
      label: (context) => context.l10n.updates,
    ),
    NavigationBarData(
      icon: FluentIcons.compass_northwest_24_regular,
      activeIcon: FluentIcons.compass_northwest_24_filled,
      motion: NavMotion.browse,
      label: (context) => context.l10n.browse,
    ),
    NavigationBarData(
      icon: FluentIcons.arrow_download_24_regular,
      activeIcon: FluentIcons.arrow_download_24_filled,
      motion: NavMotion.downloads,
      label: (context) => context.l10n.downloads,
    ),
    NavigationBarData(
      icon: FluentIcons.more_horizontal_24_regular,
      activeIcon: FluentIcons.more_horizontal_24_filled,
      motion: NavMotion.more,
      label: (context) => context.l10n.more,
    ),
  ];

  static final tabletNavList = [
    NavigationBarData(
      icon: FluentIcons.library_24_regular,
      activeIcon: FluentIcons.library_24_filled,
      motion: NavMotion.library,
      label: (context) => context.l10n.library,
    ),
    NavigationBarData(
      icon: FluentIcons.news_24_regular,
      activeIcon: FluentIcons.news_24_filled,
      motion: NavMotion.updates,
      label: (context) => context.l10n.updates,
    ),
    NavigationBarData(
      icon: FluentIcons.history_24_regular,
      activeIcon: FluentIcons.history_24_filled,
      motion: NavMotion.history,
      label: (context) => context.l10n.history,
    ),
    NavigationBarData(
      icon: FluentIcons.compass_northwest_24_regular,
      activeIcon: FluentIcons.compass_northwest_24_filled,
      motion: NavMotion.browse,
      label: (context) => context.l10n.browse,
    ),
    NavigationBarData(
      icon: FluentIcons.arrow_download_24_regular,
      activeIcon: FluentIcons.arrow_download_24_filled,
      motion: NavMotion.downloads,
      label: (context) => context.l10n.downloads,
    ),
    NavigationBarData(
      icon: FluentIcons.more_horizontal_24_regular,
      activeIcon: FluentIcons.more_horizontal_24_filled,
      motion: NavMotion.more,
      label: (context) => context.l10n.more,
    ),
  ];

  // Branch order must match the shell so navigation indices need no translation.
  static final desktopNavList = [
    NavigationBarData(
      icon: FluentIcons.library_24_regular,
      activeIcon: FluentIcons.library_24_filled,
      motion: NavMotion.library,
      label: (context) => context.l10n.library,
    ),
    NavigationBarData(
      icon: FluentIcons.news_24_regular,
      activeIcon: FluentIcons.news_24_filled,
      motion: NavMotion.updates,
      label: (context) => context.l10n.updates,
    ),
    NavigationBarData(
      icon: FluentIcons.history_24_regular,
      activeIcon: FluentIcons.history_24_filled,
      motion: NavMotion.history,
      label: (context) => context.l10n.history,
    ),
    NavigationBarData(
      icon: FluentIcons.compass_northwest_24_regular,
      activeIcon: FluentIcons.compass_northwest_24_filled,
      motion: NavMotion.browse,
      label: (context) => context.l10n.browse,
    ),
    NavigationBarData(
      icon: FluentIcons.arrow_download_24_regular,
      activeIcon: FluentIcons.arrow_download_24_filled,
      motion: NavMotion.downloads,
      label: (context) => context.l10n.downloads,
    ),
  ];

  static List<NavigationBarData> getNavList(BuildContext context) {
    return context.windowSizeClass >= WindowSizeClass.medium
        ? tabletNavList
        : phoneNavList;
  }

  static final navList = phoneNavList;

  NavigationBarData({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.motion,
  });
}
