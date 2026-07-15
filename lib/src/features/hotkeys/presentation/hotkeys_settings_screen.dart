// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../data/hotkey_binding.dart';

class HotkeysSettingsScreen extends StatelessWidget {
  const HotkeysSettingsScreen({super.key});

  // Collapse registry entries that share a label into one row, each entry's
  // keys shown as a separate chord (e.g. Go back → Esc · Alt+← · Mouse Back).
  List<_Row> _globalRows(AppLocalizations l) {
    final rows = <_Row>[];
    for (final h in activeGlobalHotkeys()) {
      final label = h.label(l);
      final existing = rows.where((r) => r.label == label);
      if (existing.isEmpty) {
        rows.add(_Row(label, [h.displayKeys]));
      } else {
        existing.first.chords.add(h.displayKeys);
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rows = [
      _SectionHeader(l.hotkeysGlobalSection),
      for (final r in _globalRows(l)) _HotkeyRow(label: r.label, chords: r.chords),
      _SectionHeader(l.hotkeysReaderSection),
      for (final h in readerHotkeyDisplays)
        _HotkeyRow(label: h.label(l), chords: [h.displayKeys]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.keyboardShortcuts)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
        ),
      ),
    );
  }
}

class _Row {
  _Row(this.label, this.chords);
  final String label;
  final List<List<String>> chords;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text,
            style: context.textTheme.titleSmall
                ?.copyWith(color: context.colorScheme.primary)),
      );
}

class _HotkeyRow extends StatelessWidget {
  const _HotkeyRow({required this.label, required this.chords});
  final String label;
  final List<List<String>> chords;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(label, style: context.textTheme.bodyLarge)),
            const SizedBox(width: 16),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 6,
                children: [for (final chord in chords) _Chord(chord)],
              ),
            ),
          ],
        ),
      );
}

// One key combination, e.g. Alt+← rendered as two adjacent caps.
class _Chord extends StatelessWidget {
  const _Chord(this.keys);
  final List<String> keys;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        children: [for (final k in keys) _KeyCap(k)],
      );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.colorScheme.outlineVariant),
        ),
        child: Text(label, style: context.textTheme.labelMedium),
      );
}
