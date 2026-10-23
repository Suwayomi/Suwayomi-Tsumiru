// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';

class SettingsGroupRow extends StatelessWidget {
  const SettingsGroupRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider());
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      ),
    );
  }
}

class SettingsGroupHeading extends StatelessWidget {
  const SettingsGroupHeading({
    super.key,
    required this.label,
    this.first = false,
  });

  final String label;

  /// The first heading on a page sits closer to the app bar.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, first ? 8 : 24, 16, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.theme.colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
