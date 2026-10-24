// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../utils/extensions/custom_extensions.dart';
import 'organizer_heading.dart';

enum FilterState {
  /// Don't filter on this (persisted as null).
  any,

  /// Show only entries that match (persisted as true).
  included,

  /// Hide entries that match (persisted as false).
  excluded;

  static FilterState fromValue(bool? value) => switch (value) {
        null => FilterState.any,
        true => FilterState.included,
        false => FilterState.excluded,
      };

  bool? get value => switch (this) {
        FilterState.any => null,
        FilterState.included => true,
        FilterState.excluded => false,
      };

  String toLocale(BuildContext context) => switch (this) {
        FilterState.any => context.l10n.filterStateAny,
        FilterState.included => context.l10n.filterStateIncluded,
        FilterState.excluded => context.l10n.filterStateExcluded,
      };
}

class TriStateFilterTile extends ConsumerWidget {
  const TriStateFilterTile({
    super.key,
    required this.header,
    required this.provider,
    required this.onChanged,
    this.includedLabel,
    this.excludedLabel,
  });

  /// Label the filter axis; the pills label its possible values.
  final String header;

  /// Reads a bool? provider; mutations flow through onChanged.
  final ProviderListenable<bool?> provider;
  final ValueChanged<bool?> onChanged;

  /// Pill label for [FilterState.included]. Defaults to the generic "Included".
  final String? includedLabel;

  /// Pill label for [FilterState.excluded]. Defaults to the generic "Excluded".
  final String? excludedLabel;

  String _labelFor(BuildContext context, FilterState state) => switch (state) {
        FilterState.any => context.l10n.filterStateAny,
        FilterState.included => includedLabel ?? state.toLocale(context),
        FilterState.excluded => excludedLabel ?? state.toLocale(context),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.theme.colorScheme;
    final current = FilterState.fromValue(ref.watch(provider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrganizerHeading(header),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final state in FilterState.values)
                FilterChip(
                  selected: current == state,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(_labelFor(context, state)),
                  selectedColor: state == FilterState.excluded
                      ? scheme.errorContainer
                      : null,
                  onSelected: (_) => onChanged(state.value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
