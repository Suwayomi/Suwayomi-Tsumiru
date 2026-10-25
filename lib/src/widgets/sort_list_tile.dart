// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

class SortListTile extends StatelessWidget {
  const SortListTile({
    super.key,
    required this.ascending,
    required this.selected,
    required this.onChanged,
    required this.onSelected,
    this.title,
    this.subtitle,
  });
  final bool ascending;
  final bool selected;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onSelected;
  final Widget? title;
  final Widget? subtitle;
  @override
  Widget build(BuildContext context) {
    IconData icon =
        ascending ? FluentIcons.arrow_sort_up_24_regular : FluentIcons.arrow_sort_down_24_regular;

    return ListTile(
      leading: selected
          ? Icon(icon, color: context.theme.colorScheme.primary)
          : SizedBox(width: context.theme.iconTheme.size),
      title: title,
      subtitle: subtitle,
      onTap: () => selected ? onChanged(!ascending) : onSelected(),
    );
  }
}
