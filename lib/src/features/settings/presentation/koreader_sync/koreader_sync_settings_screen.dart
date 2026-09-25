// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../controller/server_controller.dart';
import '../../data/user_settings.dart';
import 'data/koreader_sync_repository.dart';
import 'domain/koreader_sync_domain.dart';
import 'widgets/koreader_sync_dialog.dart';
import 'widgets/percentage_tolerance_dialog.dart';

String _strategyLabel(
  BuildContext context,
  Enum$KoreaderSyncConflictStrategy? value,
) => switch (value) {
  Enum$KoreaderSyncConflictStrategy.KEEP_LOCAL =>
    context.l10n.koreaderSyncStrategyKeepLocal,
  Enum$KoreaderSyncConflictStrategy.KEEP_REMOTE =>
    context.l10n.koreaderSyncStrategyKeepRemote,
  Enum$KoreaderSyncConflictStrategy.DISABLED =>
    context.l10n.koreaderSyncStrategyDisabled,
  _ => context.l10n.koreaderSyncStrategyPrompt,
};

String _checksumLabel(
  BuildContext context,
  Enum$KoreaderSyncChecksumMethod? value,
) => switch (value) {
  Enum$KoreaderSyncChecksumMethod.FILENAME =>
    context.l10n.koreaderSyncChecksumFilename,
  _ => context.l10n.koreaderSyncChecksumBinary,
};

class KoreaderSyncSettingsScreen extends ConsumerWidget {
  const KoreaderSyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(koreaderSyncSettingsProvider);
    final koSync = ref.watch(koSyncStatusProvider);

    void refresh() {
      ref.invalidate(settingsProvider);
      ref.invalidate(userSettingsProvider);
      ref.invalidate(koreaderSyncSettingsProvider);
      ref.invalidate(koSyncStatusProvider);
    }

    Future<void> save(Future<bool> Function() action) async {
      await AppUtils.guard(action, ref.read(toastProvider));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.koreaderSync)),
      body: settings.showUiWhenData(
        context,
        refresh: refresh,
        skipLoadingOnReload: true,
        (server) {
          final koSyncError = koSync.error;
          if (server == null ||
              (koSyncError != null &&
                  onlyUndefinedFieldErrors(
                    koSyncError,
                    type: 'Query',
                    field: 'koSyncStatus',
                  ))) {
            return Emoticons(title: l10n.koreaderSyncUnsupported);
          }
          return koSync.showUiWhenData(
            context,
            refresh: refresh,
            skipLoadingOnReload: true,
            (status) {
              return ListView(
                children: [
                  ListTile(
                    title: Text(l10n.koreaderSyncStatus),
                    subtitle: Text(
                      status.isLoggedIn
                          ? l10n.koreaderSyncConnectedAs(
                              status.username ?? '',
                              status.serverAddress ?? '',
                            )
                          : l10n.koreaderSyncStatusDisconnected,
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => KoreaderSyncDialog(status: status),
                    ),
                  ),
                  _ChoiceTile<Enum$KoreaderSyncConflictStrategy>(
                    title: l10n.koreaderSyncStrategyForward,
                    value: server.strategyForward,
                    options: koreaderSyncConflictStrategies,
                    label: (value) => _strategyLabel(context, value),
                    onSelected: (value) => save(
                      () => ref
                          .read(koreaderSyncRepositoryProvider)
                          .updateStrategyForward(value),
                    ),
                  ),
                  _ChoiceTile<Enum$KoreaderSyncConflictStrategy>(
                    title: l10n.koreaderSyncStrategyBackward,
                    value: server.strategyBackward,
                    options: koreaderSyncConflictStrategies,
                    label: (value) => _strategyLabel(context, value),
                    onSelected: (value) => save(
                      () => ref
                          .read(koreaderSyncRepositoryProvider)
                          .updateStrategyBackward(value),
                    ),
                  ),
                  _ChoiceTile<Enum$KoreaderSyncChecksumMethod>(
                    title: l10n.koreaderSyncChecksumMethod,
                    value: server.checksumMethod,
                    options: koreaderSyncChecksumMethods,
                    label: (value) => _checksumLabel(context, value),
                    onSelected: (value) => save(
                      () => ref
                          .read(koreaderSyncRepositoryProvider)
                          .updateChecksumMethod(value),
                    ),
                  ),
                  ListTile(
                    title: Text(l10n.koreaderSyncPercentageTolerance),
                    subtitle: Text(
                      formatPercentageTolerance(server.percentageTolerance),
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => PercentageToleranceDialog(
                        value: server.percentageTolerance,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.options,
    required this.label,
    required this.onSelected,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T) label;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(label(value)),
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => RadioListPopup<T>(
          title: title,
          optionList: options,
          value: value,
          getOptionTitle: label,
          onChange: (value) {
            onSelected(value);
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }
}
