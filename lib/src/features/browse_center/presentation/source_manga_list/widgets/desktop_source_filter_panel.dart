// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/filter/filter_model.dart';
import 'desktop_source_filter_fields.dart';
import 'saved_source_searches.dart';

class DesktopSourceFilterPanel extends HookWidget {
  const DesktopSourceFilterPanel({
    super.key,
    required this.filters,
    required this.sourceId,
    required this.appliedChanges,
    required this.currentQuery,
    required this.onSavedSearchSelected,
    required this.onSubmitted,
    required this.onReset,
  });

  final List<Filter> filters;
  final String sourceId;
  final List<FilterChange> appliedChanges;
  final String? Function() currentQuery;
  final void Function(String?, List<FilterChange>) onSavedSearchSelected;
  final ValueChanged<List<FilterChange>?> onSubmitted;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final filterChangeMap = useState<Map<int, List<FilterChange>>>(const {});
    final saveSearch = useRef<Future<void> Function()?>(null);
    final canSaveSearch = useState(true);

    useEffect(() {
      final changeMap = <int, List<FilterChange>>{};
      for (final change in appliedChanges) {
        changeMap[change.position] = [...?changeMap[change.position], change];
      }
      filterChangeMap.value = changeMap;
      return null;
    }, [appliedChanges]);

    List<FilterChange> collectChanges() =>
        filterChangeMap.value.values.fold(<FilterChange>[], (prev, curr) {
          prev.addAll(curr);
          return prev;
        });

    void onFilterChanged(int filterIndex, List<FilterChange> changed) {
      final filterChanges = <FilterChange>[];
      for (final filter in changed) {
        filterChanges.add(filter.copyWith(position: filterIndex));
      }
      filterChangeMap.value = {
        ...filterChangeMap.value,
        filterIndex: filterChanges,
      };
    }

    Widget filterAt(int filterIndex) => DesktopSourceFilterField(
      key: ValueKey('BaseFilter-$filterIndex'),
      filter: filters[filterIndex],
      currentChanges: filterChangeMap.value[filterIndex] ?? const [],
      onChanged: (changed) => onFilterChanged(filterIndex, changed),
    );

    final leftIndexes = <int>[];
    final rightIndexes = <int>[];
    for (var i = 0; i < filters.length; i++) {
      (filters[i] is FilterGroup ? rightIndexes : leftIndexes).add(i);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l10n.filter,
                style: context.theme.textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: canSaveSearch.value
                    ? () => saveSearch.value?.call()
                    : null,
                child: Text(context.l10n.saveSearch),
              ),
              TextButton(
                onPressed: () {
                  onReset();
                  filterChangeMap.value = const {};
                },
                child: Text(context.l10n.reset),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  onSubmitted(collectChanges());
                  Navigator.of(context).pop();
                },
                child: Text(context.l10n.filter),
              ),
            ],
          ),
          SavedSourceSearches(
            sourceId: sourceId,
            currentQuery: currentQuery,
            currentChanges: collectChanges,
            onSaveAction: (fn) => saveSearch.value = fn,
            onCanSaveChanged: (canSave) {
              if (canSaveSearch.value != canSave) {
                canSaveSearch.value = canSave;
              }
            },
            onSelected: (savedQuery, changes) {
              onSavedSearchSelected(savedQuery, changes);
              Navigator.of(context).pop();
            },
            hideHeader: true,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 240,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView(
                      shrinkWrap: true,
                      children: [for (final i in leftIndexes) filterAt(i)],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView(
                      shrinkWrap: true,
                      children: [for (final i in rightIndexes) filterAt(i)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
