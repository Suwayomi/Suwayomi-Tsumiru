// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../data/koreader_sync_repository.dart';
import '../domain/koreader_sync_domain.dart';

const String koreaderSyncDefaultServerAddress = 'https://sync.koreader.rocks/';

class KoreaderSyncDialog extends HookConsumerWidget {
  const KoreaderSyncDialog({super.key, required this.status});

  final KoSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final serverAddress = useTextEditingController(
      text: status.serverAddress ?? koreaderSyncDefaultServerAddress,
    );
    final username = useTextEditingController(text: status.username ?? '');
    final password = useTextEditingController();
    final obscure = useState(true);
    final busy = useState(false);
    final failure = useState<({String message, String? detail})?>(null);
    final repository = ref.read(koreaderSyncRepositoryProvider);

    Future<void> close() async {
      ref.invalidate(koSyncStatusProvider);
      if (context.mounted) Navigator.pop(context);
    }

    void fail(String message, String? detail) {
      failure.value = (message: message, detail: detail);
      busy.value = false;
    }

    Future<void> connect() async {
      failure.value = null;
      if (!(formKey.currentState?.validate()).ifNull()) return;
      busy.value = true;
      try {
        final result = await repository.connect(
          serverAddress: serverAddress.text.trim(),
          username: username.text,
          password: password.text,
        );
        if (!context.mounted) return;
        if (result.isLoggedIn) {
          await close();
        } else {
          fail(
            l10n.koreaderSyncConnectFailed,
            result.message ?? l10n.koreaderSyncUnknownError,
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        fail(l10n.koreaderSyncConnectFailed, e.toString());
      }
    }

    Future<void> disconnect() async {
      failure.value = null;
      busy.value = true;
      try {
        final stillLoggedIn = await repository.logout();
        if (!context.mounted) return;
        if (stillLoggedIn) {
          fail(l10n.koreaderSyncDisconnectFailed, null);
        } else {
          await close();
        }
      } catch (e) {
        if (!context.mounted) return;
        fail(l10n.koreaderSyncDisconnectFailed, e.toString());
      }
    }

    final error = failure.value;

    if (status.isLoggedIn) {
      return AlertDialog(
        title: Text(l10n.koreaderSyncDisconnectTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.koreaderSyncConnectedAs(
                status.username ?? '',
                status.serverAddress ?? '',
              ),
            ),
            if (error != null) ...[
              const Gap(12),
              _SyncErrorMessage(message: error.message, detail: error.detail),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy.value ? null : () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: busy.value ? null : disconnect,
            child: busy.value
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.koreaderSyncDisconnect),
          ),
        ],
      );
    }

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.koreaderSyncConnectTitle),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: serverAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => failure.value = null,
              decoration: InputDecoration(
                labelText: l10n.serverAddress,
                hintText: l10n.serverAddress,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(4),
            TextFormField(
              controller: username,
              validator: (v) => v.isBlank ? l10n.errorUserName : null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => failure.value = null,
              decoration: InputDecoration(
                labelText: l10n.koreaderSyncUsername,
                hintText: l10n.koreaderSyncUsername,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(4),
            TextFormField(
              controller: password,
              validator: (v) => v.isBlank ? l10n.errorPassword : null,
              obscureText: obscure.value,
              textInputAction: TextInputAction.done,
              onChanged: (_) => failure.value = null,
              onFieldSubmitted: (_) {
                if (!busy.value) connect();
              },
              decoration: InputDecoration(
                labelText: l10n.password,
                hintText: l10n.password,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure.value
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  tooltip: obscure.value
                      ? l10n.koreaderSyncShowPassword
                      : l10n.koreaderSyncHidePassword,
                  onPressed: () => obscure.value = !obscure.value,
                ),
              ),
            ),
            if (error != null) ...[
              const Gap(12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _SyncErrorMessage(
                  message: error.message,
                  detail: error.detail,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: busy.value ? null : connect,
          child: busy.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.koreaderSyncConnect),
        ),
      ],
    );
  }
}

class _SyncErrorMessage extends StatelessWidget {
  const _SyncErrorMessage({required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Theme.of(context).colorScheme.error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: style),
        if (!detail.isBlank) Text(detail!, style: style),
      ],
    );
  }
}
