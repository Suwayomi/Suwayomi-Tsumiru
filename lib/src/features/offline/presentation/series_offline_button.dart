// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/popup_widgets/confirm_action.dart';
import '../../account/data/account_permission.dart';
import '../../account/data/account_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/presentation/manga_details/widgets/manga_action_button.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import 'offline_action_confirmations.dart';

class SeriesOfflineButton extends ConsumerWidget {
  const SeriesOfflineButton({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) return const SizedBox.shrink();
    final progress = ref.watch(mangaOfflineProgressProvider(mangaId)).value;
    final downloaded = progress?.downloaded ?? 0;
    final inFlight = progress?.inFlight ?? 0;
    final onDevice = downloaded > 0;
    final downloading = inFlight > 0;
    final config = ref.watch(mangaKeepConfigProvider(mangaId)).value;
    return MangaActionButton(
      active: onDevice || downloading,
      icon: downloading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              onDevice
                  ? Icons.offline_pin_rounded
                  : Icons.download_for_offline_outlined,
            ),
      label: downloading
          ? context.l10n.offlineDownloadingCount(inFlight)
          : _ruleLabel(context, config?.rule, config?.count) ??
                (onDevice
                    ? context.l10n.offlineOnDevice
                    : context.l10n.offlineDownloadAction),
      onPressed: () => _openSheet(context, ref, onDevice),
    );
  }

  String? _ruleLabel(BuildContext context, OfflineKeepRule? rule, int? count) =>
      switch (rule) {
        OfflineKeepRule.all => context.l10n.keepOfflineAll,
        OfflineKeepRule.allUnread => context.l10n.keepOfflineAllUnread,
        OfflineKeepRule.nUnread => context.l10n.keepOfflineNextUnread(
          count ?? 5,
        ),
        OfflineKeepRule.off || null => null,
      };

  void _openSheet(BuildContext context, WidgetRef ref, bool onDevice) {
    final config =
        ref.read(mangaKeepConfigProvider(mangaId)).value ??
        (rule: OfflineKeepRule.off, count: 5);
    final rule = config.rule;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The library-update strip shrinks available height; avoid the default 9/16 sheet cap.
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final canDownload = sheetRef
              .watch(settledAccountAccessProvider)
              .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canDownload)
                    ListTile(
                      subtitle: Text(context.l10n.accountPermissionDenied),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sheetContext.l10n.offlineSheetTitle,
                          style: sheetContext.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sheetContext.l10n.offlineSheetSubtitle,
                          style: TextStyle(
                            color:
                                sheetContext.theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  for (final n in const [5, 10, 25])
                    ListTile(
                      leading: const Icon(Icons.bookmark_add_outlined),
                      title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                      trailing:
                          (rule == OfflineKeepRule.nUnread && config.count == n)
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: canDownload
                          ? () => _apply(
                              sheetContext,
                              ref,
                              OfflineKeepRule.nUnread,
                              n,
                            )
                          : null,
                    ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(sheetContext.l10n.keepOfflineAllUnread),
                    trailing: rule == OfflineKeepRule.allUnread
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: canDownload
                        ? () => _apply(
                            sheetContext,
                            ref,
                            OfflineKeepRule.allUnread,
                            config.count,
                          )
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.library_books_outlined),
                    title: Text(sheetContext.l10n.keepOfflineAll),
                    trailing: rule == OfflineKeepRule.all
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: canDownload
                        ? () => _apply(
                            sheetContext,
                            ref,
                            OfflineKeepRule.all,
                            config.count,
                          )
                        : null,
                  ),
                  if (onDevice || rule != OfflineKeepRule.off) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: sheetContext.theme.colorScheme.error,
                      ),
                      title: Text(
                        sheetContext.l10n.offlineRemoveSeries,
                        style: TextStyle(
                          color: sheetContext.theme.colorScheme.error,
                        ),
                      ),
                      onTap: () async {
                        final current = ref
                            .read(authCredentialsStoreProvider.notifier)
                            .captureSession();
                        if (!await confirmAction(
                              sheetContext,
                              title: sheetContext.l10n.removeFromDevice,
                              message: sheetContext
                                  .l10n
                                  .confirmDeleteSeriesDeviceMessage,
                              action: sheetContext.l10n.removeFromDevice,
                            ) ||
                            !sheetContext.mounted ||
                            !current()) {
                          return;
                        }
                        await _removeAll(sheetContext, ref);
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      sheetAnimationStyle: context.motionStyle,
    );
  }

  Future<void> _apply(
    BuildContext sheetContext,
    WidgetRef ref,
    OfflineKeepRule rule,
    int count,
  ) async {
    final messenger = ScaffoldMessenger.of(sheetContext);
    final snackBarMotionStyle = sheetContext.snackBarMotionStyle;
    final toast = sheetContext.l10n.offlineDownloadingToast;
    Navigator.of(sheetContext).pop();
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    ref
        .read(accountPermissionGuardProvider)
        .require(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    if (!await confirmAndChangeKeepRule(ref, mangaId, rule, count)) return;
    if (!ref.context.mounted || !current()) return;
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
    messenger.showSnackBar(
      SnackBar(content: Text(toast)),
      snackBarAnimationStyle: snackBarMotionStyle,
    );
  }

  Future<void> _removeAll(BuildContext sheetContext, WidgetRef ref) async {
    Navigator.of(sheetContext).pop();
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    await removeKeepRuleAndDelete(ref, mangaId);
    if (!ref.context.mounted || !current()) return;
    ref.invalidate(mangaKeepRuleProvider(mangaId));
    ref.invalidate(mangaKeepConfigProvider(mangaId));
    ref.invalidate(mangaDownloadedCountProvider(mangaId));
  }
}
