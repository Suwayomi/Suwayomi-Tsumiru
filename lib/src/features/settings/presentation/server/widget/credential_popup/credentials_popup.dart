// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/endpoints.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../features/auth/data/auth_coordinator.dart';
import '../../../../../../features/auth/data/auth_credentials_store.dart';
import '../../../../../../features/auth/data/basic_auth_migration.dart';
import '../../../../../../features/auth/data/secure_credentials_provider.dart';
import '../../../../../../features/auth/presentation/auth_failure_text.dart';
import '../../../../../../features/auth/presentation/sign_in_action.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import '../client/server_port_tile/server_port_tile.dart';
import '../client/server_url_tile/server_url_tile.dart';

part 'credentials_popup.g.dart';

// keepAlive, like AuthCredentialsStore: main() preloads it so images, links
// and background work can read `.value` synchronously. Auto-disposed, the
// preload was dropped at once, those reads saw null, and the first watch
// rebuilt the GraphQL client under requests already on their way.
@Riverpod(keepAlive: true)
class Credentials extends _$Credentials {
  @override
  Future<String?> build() async =>
      ref.read(secureStorageProvider).read(key: kBasicCredentialsSecureKey);

  /// [forEpoch]: discards/undoes the write if a switch bumps [AuthCredentialsStore.serverEpoch]
  /// meanwhile. Omit for a clear (set null).
  Future<void> set(String? value, {int? forEpoch}) async {
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
  }
}

final formKey = GlobalKey<FormState>();

class CredentialsPopup extends HookConsumerWidget {
  const CredentialsPopup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = useTextEditingController();
    final password = useTextEditingController();
    final saving = useState(false);
    final error = useState<String?>(null);
    Future<void> doSave() async {
      if (!(formKey.currentState?.validate()).ifNull()) return;
      saving.value = true;
      error.value = null;
      try {
        // Verified before it is stored. Saving blind reported a successful
        // sign-in for a mistyped password and then 401'd every request.
        await performSignIn(
          ref,
          authType: AuthType.basic,
          serverBaseUrl: Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            appendApiToUrl: false,
          ),
          username: username.text,
          password: password.text,
        );
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (!context.mounted) return;
        error.value = authFailureText(context, classifyAuthError(e).kind);
      } finally {
        if (context.mounted) saving.value = false;
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
            if (error.value != null) ...[
              const Gap(8),
              Text(
                error.value!,
                style: TextStyle(color: context.theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        const PopButton(),
        ElevatedButton(
          onPressed: saving.value ? null : doSave,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
