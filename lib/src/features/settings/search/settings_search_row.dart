// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../utils/extensions/custom_extensions.dart';
import 'settings_search_entry.dart';

/// One Settings search row, option A: muted tune icon, title with the matched
/// text in the primary colour and semi-bold, page breadcrumb underneath in
/// `bodySmall` / `onSurfaceVariant`. A plain [ListTile] like the neighbouring
/// library and Go to rows, so row height, padding and keyboard focus behave
/// the same. Shared by the desktop dropdown and the phone search overlay.
class SettingsSearchResultRow extends StatelessWidget {
  const SettingsSearchResultRow({
    super.key,
    required this.entry,
    required this.query,
    required this.onTap,
  });

  final SettingsSearchEntry entry;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = context.colorScheme;
    return ListTile(
      leading: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
      title: Text.rich(
        TextSpan(
          children: settingsTitleSpans(
            title: entry.title(l),
            query: query,
            match: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
          ),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        entry.breadcrumb(l),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
