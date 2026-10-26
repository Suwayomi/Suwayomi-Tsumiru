// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../../../../constants/app_constants.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/filter/filter_model.dart';
import 'filter_to_widget.dart';

class DesktopSourceFilterField extends StatelessWidget {
  const DesktopSourceFilterField({
    super.key,
    required this.filter,
    required this.currentChanges,
    required this.onChanged,
  });

  final Filter filter;
  final List<FilterChange> currentChanges;
  final ValueChanged<List<FilterChange>> onChanged;

  @override
  Widget build(BuildContext context) {
    final filter = this.filter;
    return switch (filter) {
      FilterSort(
        name: String name,
        sortState: SortSelectionDto state,
        displayValues: List<String> values,
      ) =>
        _DesktopSortField(
          name: name,
          sortState: state,
          displayValues: values,
          currentChanges: currentChanges,
          onChanged: onChanged,
        ),
      FilterSelect(
        name: String name,
        selectState: int state,
        displayValues: List<String> displayValues,
      ) =>
        _DesktopSelectField(
          name: name,
          selectState: state,
          displayValues: displayValues,
          currentChanges: currentChanges,
          onChanged: onChanged,
        ),
      FilterGroup(name: String name, groupState: List<PrimitiveFilter> state) =>
        FilterGroupWidget(
          name: name,
          filters: state,
          currentChanges: currentChanges,
          onChanged: onChanged,
          expanded: true,
          singleLineLabels: true,
        ),
      _ => FilterToWidget(
        filter: filter,
        currentChanges: currentChanges,
        onChanged: onChanged,
      ),
    };
  }
}

class _DesktopSortField extends StatelessWidget {
  const _DesktopSortField({
    required this.name,
    required this.sortState,
    required this.displayValues,
    required this.currentChanges,
    required this.onChanged,
  });

  final String name;
  final SortSelectionDto sortState;
  final List<String> displayValues;
  final List<FilterChange> currentChanges;
  final ValueChanged<List<FilterChange>> onChanged;

  @override
  Widget build(BuildContext context) {
    final firstCurrentChange = currentChanges.firstOrNull;
    final selectedIndex =
        firstCurrentChange?.sortState?.index ?? sortState.index;
    final ascending =
        (firstCurrentChange?.sortState?.ascending ?? sortState.ascending)
            .ifNull(true);
    void select(int index) => onChanged([
      FilterChange(
        sortState: SortStateChange(ascending: true, index: index),
        position: kPositionPlaceholder,
      ),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: context.textTheme.labelLarge),
        RadioGroup<int>(
          groupValue: selectedIndex,
          onChanged: (value) {
            if (value != null) select(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (
                int i = 0;
                i < (displayValues.length).getValueOnNullOrNegative();
                i++
              )
                RadioListTile<int>(
                  value: i,
                  title: Text(
                    displayValues[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  contentPadding: EdgeInsets.zero,
                  horizontalTitleGap: 8,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  secondary: i == selectedIndex
                      ? IconButton(
                          icon: Icon(
                            ascending
                                ? FluentIcons.arrow_sort_up_24_regular
                                : FluentIcons.arrow_sort_down_24_regular,
                          ),
                          onPressed: () => onChanged([
                            FilterChange(
                              sortState: SortStateChange(
                                ascending: !ascending,
                                index: i,
                              ),
                              position: kPositionPlaceholder,
                            ),
                          ]),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopSelectField extends StatelessWidget {
  const _DesktopSelectField({
    required this.name,
    required this.selectState,
    required this.displayValues,
    required this.currentChanges,
    required this.onChanged,
  });

  final String name;
  final int selectState;
  final List<String> displayValues;
  final List<FilterChange> currentChanges;
  final ValueChanged<List<FilterChange>> onChanged;

  @override
  Widget build(BuildContext context) {
    final firstCurrentChange = currentChanges.firstOrNull;
    final effectiveValue = firstCurrentChange?.selectState ?? selectState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: context.textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          key: ValueKey(effectiveValue),
          isExpanded: true,
          initialValue: effectiveValue,
          items: [
            for (
              int i = 0;
              i < (displayValues.length).getValueOnNullOrNegative();
              i++
            )
              DropdownMenuItem(
                value: i,
                child: Text(
                  displayValues[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall,
                ),
              ),
          ],
          onChanged: (value) => onChanged([
            FilterChange(selectState: value, position: kPositionPlaceholder),
          ]),
        ),
      ],
    );
  }
}
