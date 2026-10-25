// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../tsumiru_logo.dart';
import 'desktop_title_bar.dart';

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
            child: Text(kAppName, style: brandNameStyle(context)),
          ),
          IconButton(
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            tooltip: context.l10n.collapseSidebar,
            onPressed: onCollapse,
          ),
        ],
      ),
    ),
  );
}

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
