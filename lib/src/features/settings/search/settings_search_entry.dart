// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';

/// One searchable setting: a row in the Settings search section that opens
/// its page scrolled to the matching tile.
///
/// [id] is stable across renames and doubles as the `highlight` query value
/// the page's [SettingsHighlightTarget] matches on. [breadcrumb] names the
/// page and, where the page has section headers, the section
/// ("Library › Global Update"). [open] pushes the page's typed route with the
/// id. [visible] mirrors exactly when the tile is rendered on its screen —
/// platform gates, "only when another switch is on" gates — using the same
/// providers the screen reads, so search never offers a tile that isn't
/// there. Tiles that render disabled (permission gates) still count as
/// visible: the tile is on screen, just not tappable.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.title,
    this.subtitle,
    required this.breadcrumb,
    required this.open,
    required this.visible,
  });

  final String id;
  final String Function(AppLocalizations l) title;
  final String Function(AppLocalizations l)? subtitle;
  final String Function(AppLocalizations l) breadcrumb;
  final void Function(BuildContext context) open;
  final bool Function(WidgetRef ref, BuildContext context) visible;
}

/// Maximum settings rows per query, Komikku's rule.
const int kSettingsSearchLimit = 10;

/// Case-insensitive substring match on title and subtitle, in registry order,
/// capped at [kSettingsSearchLimit]. Empty queries match nothing. Visibility
/// is decided by [isVisible] so hosts can pass their ref+context while unit
/// tests pass a stub.
List<SettingsSearchEntry> matchSettingsEntries({
  required List<SettingsSearchEntry> entries,
  required AppLocalizations l,
  required String query,
  required bool Function(SettingsSearchEntry entry) isVisible,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <SettingsSearchEntry>[];
  for (final entry in entries) {
    if (!isVisible(entry)) continue;
    if (entry.title(l).toLowerCase().contains(q) ||
        (entry.subtitle?.call(l).toLowerCase().contains(q) ?? false)) {
      out.add(entry);
      if (out.length >= kSettingsSearchLimit) break;
    }
  }
  return out;
}

/// Splits [title] around the first case-insensitive occurrence of [query] so
/// a row can paint the match in the primary colour. Returns a single plain
/// span when the query is blank or only matches the subtitle.
List<TextSpan> settingsTitleSpans({
  required String title,
  required String query,
  TextStyle? base,
  required TextStyle match,
}) {
  final q = query.trim();
  if (q.isEmpty) return [TextSpan(text: title, style: base)];
  final index = title.toLowerCase().indexOf(q.toLowerCase());
  if (index < 0) return [TextSpan(text: title, style: base)];
  return [
    TextSpan(text: title.substring(0, index), style: base),
    TextSpan(text: title.substring(index, index + q.length), style: match),
    TextSpan(text: title.substring(index + q.length), style: base),
  ];
}
