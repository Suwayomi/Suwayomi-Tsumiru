// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../tsumiru_logo.dart';
import 'desktop_title_bar.dart';

/// The expanded brand block: the logo (tap opens About), the app name and the
/// collapse chevron. Shared by the merged top bar and the macOS sidebar so the
/// two draw the same row.
class DesktopBrandRow extends StatelessWidget {
  const DesktopBrandRow({
    super.key,
    required this.onCollapse,
    this.height,
    this.padding = const EdgeInsets.only(left: 16, right: 4),
  });

  final VoidCallback onCollapse;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Padding(
      padding: padding,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => const AboutRoute().push(context),
            child: const TsumiruLogo(size: kBrandLogoSize),
          ),
          const SizedBox(width: kBrandGap),
          Expanded(
            child: Text('Tsumiru', style: brandNameStyle(context)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: context.l10n.collapseSidebar,
            onPressed: onCollapse,
          ),
        ],
      ),
    ),
  );
}

/// The collapsed brand: the logo alone as the expand button, shared by the
/// merged top bar and the macOS sidebar.
class DesktopBrandExpandButton extends StatelessWidget {
  const DesktopBrandExpandButton({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const TsumiruLogo(size: kBrandLogoSize),
    tooltip: context.l10n.expandSidebar,
    onPressed: onExpand,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(),
  );
}
