// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/compact_switch.dart';
import '../../domain/migration_models.dart';

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
  static const defaults = MigrationRunConfig(
    migrateChapters: true,
    migrateCategories: true,
    migrateTracking: true,
    migrateReaderSettings: true,
    migrateOfflineSettings: true,
    migrateDownloads: false,
    hideUnmatched: false,
    hideWithoutUpdates: false,
  );

  MigrationOption toOption({required bool deleteSource}) => MigrationOption(
    migrateChapters: migrateChapters,
    migrateCategories: migrateCategories,
    migrateTracking: migrateTracking,
    migrateReaderSettings: migrateReaderSettings,
    migrateOfflineSettings: migrateOfflineSettings,
    migrateDownloads: migrateDownloads,
    deleteSource: deleteSource,
  );

  MigrationRunConfig copyWith({
    bool? migrateChapters,
    bool? migrateCategories,
    bool? migrateTracking,
    bool? migrateReaderSettings,
    bool? migrateOfflineSettings,
    bool? migrateDownloads,
    bool? hideUnmatched,
    bool? hideWithoutUpdates,
  }) => MigrationRunConfig(
    migrateChapters: migrateChapters ?? this.migrateChapters,
    migrateCategories: migrateCategories ?? this.migrateCategories,
    migrateTracking: migrateTracking ?? this.migrateTracking,
    migrateReaderSettings: migrateReaderSettings ?? this.migrateReaderSettings,
    migrateOfflineSettings:
        migrateOfflineSettings ?? this.migrateOfflineSettings,
    migrateDownloads: migrateDownloads ?? this.migrateDownloads,
    hideUnmatched: hideUnmatched ?? this.hideUnmatched,
    hideWithoutUpdates: hideWithoutUpdates ?? this.hideWithoutUpdates,
  );
}

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
    final config = useState(MigrationRunConfig.defaults);
    final extraSearch = useTextEditingController();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: MigrationConfigOptions(
              config: config.value,
              onChanged: (value) => config.value = value,
              extraSearch: extraSearch,
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
                    config.value,
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

class MigrationConfigOptions extends StatelessWidget {
  const MigrationConfigOptions({
    super.key,
    required this.config,
    required this.onChanged,
    required this.extraSearch,
  });

  final MigrationRunConfig config;
  final ValueChanged<MigrationRunConfig> onChanged;
  final TextEditingController extraSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.migrationDataToMigrateHeader,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                _FlagChip(
                  label: l10n.migrateChapters,
                  selected: config.migrateChapters,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateChapters: v)),
                ),
                _FlagChip(
                  label: l10n.migrateCategories,
                  selected: config.migrateCategories,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateCategories: v)),
                ),
                _FlagChip(
                  label: l10n.migrateTracking,
                  selected: config.migrateTracking,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateTracking: v)),
                ),
                _FlagChip(
                  label: l10n.migrateReaderSettings,
                  selected: config.migrateReaderSettings,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateReaderSettings: v)),
                ),
                _FlagChip(
                  label: l10n.migrateOfflineSettings,
                  selected: config.migrateOfflineSettings,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateOfflineSettings: v)),
                ),
                _FlagChip(
                  label: l10n.migrateDownloads,
                  selected: config.migrateDownloads,
                  onSelected: (v) =>
                      onChanged(config.copyWith(migrateDownloads: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: extraSearch,
              decoration: InputDecoration(
                labelText: l10n.migrationAdditionalSearchQuery,
                helperText: l10n.migrationAdditionalSearchQueryHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          CompactSwitchListTile(
            title: Text(l10n.migrationHideUnmatched),
            value: config.hideUnmatched,
            onChanged: (v) => onChanged(config.copyWith(hideUnmatched: v)),
          ),
          CompactSwitchListTile(
            title: Text(l10n.migrationHideWithoutUpdates),
            subtitle: Text(l10n.migrationHideWithoutUpdatesSubtitle),
            value: config.hideWithoutUpdates,
            onChanged: (v) => onChanged(config.copyWith(hideWithoutUpdates: v)),
          ),
        ],
      ),
    );
  }
}
