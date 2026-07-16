// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../tracking/data/tracker_repository.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/library_group.dart';
import '../controller/library_grouping.dart';

/// The "Group" tab inside [LibraryMangaOrganizer].
///
/// Shows four selectable modes; tapping one persists the choice via
/// [libraryGroupTypeProvider].
class LibraryMangaGroup extends ConsumerWidget {
  const LibraryMangaGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;

    final modes = [
      (value: LibraryGroup.byDefault, label: context.l10n.groupByDefault),
      (value: LibraryGroup.bySource, label: context.l10n.groupBySource),
      (value: LibraryGroup.byStatus, label: context.l10n.groupByStatus),
      if (hasTrackers)
        (value: LibraryGroup.byTrackStatus, label: context.l10n.groupByTrackStatus),
      (value: LibraryGroup.ungrouped, label: context.l10n.groupUngrouped),
    ];

    return ListView(
      shrinkWrap: true,
      children: [
        for (final mode in modes)
          RadioListTile<int>(
            value: mode.value,
            groupValue: current,
            title: Text(mode.label),
            onChanged: (val) =>
                ref.read(libraryGroupTypeProvider.notifier).update(val),
          ),
      ],
    );
  }
}
