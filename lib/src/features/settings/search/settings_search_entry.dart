// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';

/// [id] is stable across renames and identifies the tile to highlight.
/// [visible] must match tile mounting conditions; disabled tiles remain searchable.
/// [open] must select [tabIndex] for tabbed pages before seeking the highlight.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.id,
    required this.title,
    this.subtitle,
    required this.breadcrumb,
    required this.open,
    required this.visible,
    this.tabIndex,
  });

  final String id;
  final String Function(AppLocalizations l) title;
  final String Function(AppLocalizations l)? subtitle;
  final String Function(AppLocalizations l) breadcrumb;
  final void Function(BuildContext context) open;
  final bool Function(WidgetRef ref, BuildContext context) visible;
  final int? tabIndex;
}

const int kSettingsSearchLimit = 10;

/// Matches title/subtitle substrings case-insensitively in registry order, up to [kSettingsSearchLimit].
/// Empty queries match nothing; [isVisible] supplies tile visibility.
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

/// Highlights the first case-insensitive title match; blank or subtitle-only matches stay plain.
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
