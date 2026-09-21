// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../account/data/account_session_storage.dart';
import '../data/account_storage_recovery.dart';
import '../data/account_storage_recovery_state.dart';

class AccountStorageRecoveryBanner extends ConsumerWidget {
  const AccountStorageRecoveryBanner({super.key, this.insetTop = false});

  final bool insetTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(accountStorageRecoveryProvider);
    if (recovery == null) return const SizedBox.shrink();
    final conflicts = recovery.conflicts;
    final failed = recovery.phase == AccountStorageRecoveryPhase.failed;
    return SafeArea(
      top: insetTop,
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MaterialBanner(
            leading: Icon(
              failed ? Icons.error_outline : Icons.download_rounded,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    conflicts.isNotEmpty
                        ? context.l10n.offlineRecoveryConflicts
                        : failed
                        ? context.l10n.offlineRecoveryFailed
                        : context.l10n.offlineRecoveryRunning,
                  ),
                ),
                if (!failed && recovery.completed > 0)
                  Text(
                    context.l10n.offlineRecoveryCompleted(recovery.completed),
                  ),
              ],
            ),
            actions: [
              if (conflicts.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final storage = ref.read(accountSessionStorageProvider);
                    final choice = await showDialog<Map<int, bool>>(
                      context: context,
                      builder: (_) => _ProgressChoices(conflicts: conflicts),
                    );
                    if (!context.mounted ||
                        choice == null ||
                        !identical(
                          ref.read(accountStorageRecoveryProvider),
                          recovery,
                        )) {
                      return;
                    }
                    await storage.recover(progressChoices: choice);
                  },
                  child: Text(context.l10n.offlineRecoveryReview),
                )
              else if (failed)
                TextButton(
                  onPressed: () =>
                      ref.read(accountSessionStorageProvider).recover(),
                  child: Text(context.l10n.retry),
                )
              else
                TextButton(
                  onPressed: () => const DownloadsRoute().go(context),
                  child: Text(context.l10n.downloads),
                ),
            ],
          ),
          if (!failed) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _ProgressChoices extends StatefulWidget {
  const _ProgressChoices({required this.conflicts});
  final List<AccountProgressConflict> conflicts;

  @override
  State<_ProgressChoices> createState() => _ProgressChoicesState();
}

class _ProgressChoicesState extends State<_ProgressChoices> {
  final choices = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String details(int page, bool read, bool bookmarked) => [
      l10n.page(page + 1),
      read ? l10n.offlineRecoveryRead : l10n.unread,
      bookmarked ? l10n.bookmarked : l10n.offlineRecoveryNotBookmarked,
    ].join(' · ');
    return AlertDialog(
      title: Text(l10n.offlineRecoveryReview),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * .6,
        child: ListView.builder(
          itemCount: widget.conflicts.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Text(l10n.offlineRecoveryConflicts),
                  Wrap(
                    children: [
                      for (final original in [false, true])
                        TextButton(
                          onPressed: () => setState(() {
                            for (final conflict in widget.conflicts) {
                              choices[conflict.chapterId] = original;
                            }
                          }),
                          child: Text(
                            original
                                ? l10n.offlineRecoveryOriginalAll
                                : l10n.offlineRecoveryCurrentAll,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }
            final conflict = widget.conflicts[index - 1];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                Text(conflict.name, style: context.textTheme.titleMedium),
                for (final original in [false, true])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      choices[conflict.chapterId] == original
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(
                      original
                          ? l10n.offlineRecoveryOriginal
                          : l10n.offlineRecoveryCurrent,
                    ),
                    subtitle: Text(
                      original
                          ? details(
                              conflict.originalPage,
                              conflict.originalRead,
                              conflict.originalBookmarked,
                            )
                          : details(
                              conflict.currentPage,
                              conflict.currentRead,
                              conflict.currentBookmarked,
                            ),
                    ),
                    onTap: () =>
                        setState(() => choices[conflict.chapterId] = original),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: choices.length == widget.conflicts.length
              ? () => Navigator.pop(context, choices)
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
