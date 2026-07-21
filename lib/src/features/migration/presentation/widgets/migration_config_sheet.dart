// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../utils/extensions/custom_extensions.dart';

/// What the config sheet returns: which data carries over and how the list
/// filters. Copy-vs-Migrate is deliberately NOT here — Komikku decides that on
/// the migration list screen's top bar.
class MigrationRunConfig {
  const MigrationRunConfig({
    required this.migrateChapters,
    required this.migrateCategories,
    required this.migrateTracking,
    required this.migrateReaderSettings,
    required this.migrateOfflineSettings,
    required this.migrateDownloads,
    required this.hideUnmatched,
    required this.hideWithoutUpdates,
  });

  final bool migrateChapters;
  final bool migrateCategories;
  final bool migrateTracking;
  final bool migrateReaderSettings;
  final bool migrateOfflineSettings;
  final bool migrateDownloads;
  final bool hideUnmatched;
  final bool hideWithoutUpdates;
}

/// Bottom sheet — "Data to migrate" (Komikku `MigrationConfigScreenSheet`). The
/// carry-over flags are filter chips; hide options are switches; an additional
/// search query can be appended. Continue starts the migration list.
class MigrationConfigSheet extends HookWidget {
  const MigrationConfigSheet({
    super.key,
    required this.isSingleEntry,
    required this.onStart,
  });

  final bool isSingleEntry;
  final void Function(MigrationRunConfig config, String? extraSearchQuery)
      onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.theme;

    final chapters = useState(true);
    final categories = useState(true);
    final tracking = useState(true);
    final readerSettings = useState(true);
    final offlineSettings = useState(true);
    // Opt-in: moving/re-fetching downloads costs bandwidth and disk.
    final downloads = useState(false);
    final hideUnmatched = useState(false);
    final hideWithoutUpdates = useState(false);
    final extraSearch = useTextEditingController();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      l10n.migrationDataToMigrateHeader,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _FlagChip(
                          label: l10n.migrateChapters,
                          selected: chapters.value,
                          onSelected: (v) => chapters.value = v,
                        ),
                        _FlagChip(
                          label: l10n.migrateCategories,
                          selected: categories.value,
                          onSelected: (v) => categories.value = v,
                        ),
                        _FlagChip(
                          label: l10n.migrateTracking,
                          selected: tracking.value,
                          onSelected: (v) => tracking.value = v,
                        ),
                        _FlagChip(
                          label: l10n.migrateReaderSettings,
                          selected: readerSettings.value,
                          onSelected: (v) => readerSettings.value = v,
                        ),
                        _FlagChip(
                          label: l10n.migrateOfflineSettings,
                          selected: offlineSettings.value,
                          onSelected: (v) => offlineSettings.value = v,
                        ),
                        _FlagChip(
                          label: l10n.migrateDownloads,
                          selected: downloads.value,
                          onSelected: (v) => downloads.value = v,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: extraSearch,
                      decoration: InputDecoration(
                        labelText: l10n.migrationAdditionalSearchQuery,
                        helperText: l10n.migrationAdditionalSearchQueryHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(l10n.migrationHideUnmatched),
                    value: hideUnmatched.value,
                    onChanged: (v) => hideUnmatched.value = v,
                  ),
                  SwitchListTile(
                    title: Text(l10n.migrationHideWithoutUpdates),
                    subtitle: Text(l10n.migrationHideWithoutUpdatesSubtitle),
                    value: hideWithoutUpdates.value,
                    onChanged: (v) => hideWithoutUpdates.value = v,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final q = extraSearch.text.trim();
                  onStart(
                    MigrationRunConfig(
                      migrateChapters: chapters.value,
                      migrateCategories: categories.value,
                      migrateTracking: tracking.value,
                      migrateReaderSettings: readerSettings.value,
                      migrateOfflineSettings: offlineSettings.value,
                      migrateDownloads: downloads.value,
                      hideUnmatched: hideUnmatched.value,
                      hideWithoutUpdates: hideWithoutUpdates.value,
                    ),
                    q.isEmpty ? null : q,
                  );
                },
                child: Text(l10n.migrationContinue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: true,
      );
}
