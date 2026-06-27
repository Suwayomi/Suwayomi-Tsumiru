// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../data/graphql/__generated__/query.graphql.dart';
import '../../../data/tracker_repository.dart';
import 'login_to_tracker.dart';

class SettingsTrackerTile extends ConsumerWidget {
  const SettingsTrackerTile({super.key, required this.tracker});

  final Fragment$TrackerDto tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Image.network(
        tracker.icon,
        width: 40,
        height: 40,
        errorBuilder: (_, __, ___) => const Icon(Icons.sync_rounded),
      ),
      title: Text(tracker.name),
      subtitle: tracker.isLoggedIn && tracker.isTokenExpired
          ? Text(
              context.l10n.reLogin,
              style: TextStyle(color: context.theme.colorScheme.error),
            )
          : null,
      trailing: TextButton(
        onPressed: () async {
          if (tracker.isLoggedIn) {
            await AppUtils.guard(
              () => ref
                  .read(trackerRepositoryProvider)
                  .logout(tracker.id),
              ref.read(toastProvider),
            );
            if (context.mounted) ref.invalidate(trackersProvider);
          } else {
            await loginToTracker(ref, tracker);
          }
        },
        child: Text(
          tracker.isLoggedIn ? context.l10n.logOut : context.l10n.logIn,
        ),
      ),
    );
  }
}
