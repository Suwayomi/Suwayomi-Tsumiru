// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../account/data/account_providers.dart';
import '../controller/extension_actions.dart';

class InstallExtensionFile extends ConsumerWidget {
  const InstallExtensionFile({super.key});

  void extensionFilePicker(WidgetRef ref, BuildContext context) async {
    final toast = ref.read(toastProvider);
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (!context.mounted || file == null) return;
    toast?.show(context.l10n.installingExtension);
    AppUtils.guard(() async {
      await ref.read(extensionActionsProvider).installFile(context, file: file);
      if (context.mounted) {
        toast?.show(context.l10n.extensionInstalled, instantShow: true);
      }
    }, toast);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.INSTALL_EXTERNAL_EXTENSIONS);
    return IconButton(
      tooltip: allowed
          ? context.l10n.install
          : context.l10n.accountPermissionDenied,
      icon: const Icon(Icons.add_rounded),
      onPressed: allowed ? () => extensionFilePicker(ref, context) : null,
    );
  }
}
