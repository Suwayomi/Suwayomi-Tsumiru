// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../features/auth/data/auth_credentials_store.dart';
import '../../../../../../features/auth/data/basic_auth_migration.dart';
import '../../../../../../features/auth/data/secure_credentials_provider.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../../offline/data/background/background_download_controller_shim.dart';

part 'credentials_popup.g.dart';

@riverpod
class Credentials extends _$Credentials {
  @override
  Future<String?> build() async =>
      ref.read(secureStorageProvider).read(key: kBasicCredentialsSecureKey);

  /// [forEpoch]: discards/undoes the write if a switch bumps [AuthCredentialsStore.serverEpoch]
  /// meanwhile. Omit for a clear (set null).
  Future<void> set(String? value, {int? forEpoch}) async {
    final lease = ref.keepAlive();
    try {
      await ref.read(authCredentialsStoreProvider.notifier).replaceCredentials((
        epoch,
      ) async {
        await future;
        final storage = ref.read(secureStorageProvider);
        final credentials = ref.read(authCredentialsStoreProvider.notifier);
        if (epoch != credentials.serverEpoch) return;
        if (value == null) {
          state = const AsyncData(null);
          await storage.delete(key: kBasicCredentialsSecureKey);
          return;
        }
        await storage.write(key: kBasicCredentialsSecureKey, value: value);
        if (epoch != credentials.serverEpoch) {
          await storage.delete(key: kBasicCredentialsSecureKey);
          return;
        }
        state = AsyncData(value);
      }, forEpoch: forEpoch);
    } finally {
      lease.close();
    }
  }
}

final formKey = GlobalKey<FormState>();

class CredentialsPopup extends HookConsumerWidget {
  const CredentialsPopup({super.key});

  String _basicAuth({required String userName, required String password}) =>
      'Basic ${base64.encode(utf8.encode('$userName:$password'))}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = useTextEditingController();
    final password = useTextEditingController();
    Future<void> doSave() async {
      if ((formKey.currentState?.validate()).ifNull()) {
        await ref.read(backgroundDownloadControllerProvider).changeIdentity(
          () async {
            await ref
                .read(credentialsProvider.notifier)
                .set(
                  _basicAuth(userName: username.text, password: password.text),
                  forEpoch: ref
                      .read(authCredentialsStoreProvider.notifier)
                      .serverEpoch,
                );
          },
        );
        if (context.mounted) Navigator.pop(context);
      }
    }

    return AlertDialog(
      title: Text(context.l10n.credentials),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: username,
              validator: (value) =>
                  value.isBlank ? (context.l10n.errorUserName) : null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: context.l10n.userName,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(4),
            TextFormField(
              controller: password,
              validator: (value) =>
                  value.isBlank ? (context.l10n.errorPassword) : null,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => doSave(),
              decoration: InputDecoration(
                hintText: context.l10n.password,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        const PopButton(),
        ElevatedButton(onPressed: doSave, child: Text(context.l10n.save)),
      ],
    );
  }
}
