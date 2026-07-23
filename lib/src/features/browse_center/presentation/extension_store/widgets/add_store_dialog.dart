// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../data/extension_store_repository/extension_store_repository.dart';

/// Mirrors Komikku's ExtensionStoreCreateDialog. Duplicate check is an exact
/// string match against the caller's current store URLs (not a normalized
/// compare) — same URL byte-for-byte is what the server itself rejects.
class AddStoreDialog extends HookConsumerWidget {
  const AddStoreDialog({super.key, required this.existingUrls});

  final Set<String> existingUrls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final url = useState('');
    final submitting = useState(false);
    final serverError = useState<String?>(null);

    final trimmed = url.value.trim();
    final isDuplicate = existingUrls.contains(trimmed);
    final canSubmit = trimmed.isNotEmpty && !isDuplicate && !submitting.value;

    Future<void> submit() async {
      submitting.value = true;
      serverError.value = null;
      try {
        await ref.read(extensionStoreRepositoryProvider).addStore(trimmed);
        if (context.mounted) {
          // ignore: unused_result
          ref.refresh(extensionStoreListProvider.future);
          Navigator.pop(context);
        }
      } catch (e) {
        // The dialog stays open on failure — a raw server exception can carry
        // HTML/stack noise, so keep only the first line, clamped.
        final firstLine = e.toString().split('\n').first;
        submitting.value = false;
        serverError.value =
            firstLine.length > 200 ? firstLine.substring(0, 200) : firstLine;
      }
    }

    return AlertDialog(
      title: Text(context.l10n.addExtensionStore),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        maxLines: 1,
        onChanged: (value) {
          url.value = value;
          if (serverError.value != null) serverError.value = null;
        },
        decoration: InputDecoration(
          labelText: context.l10n.storeIndexUrl,
          errorText: isDuplicate
              ? context.l10n.extensionStoreAlreadyExists
              : serverError.value,
        ),
      ),
      actions: [
        const PopButton(),
        ElevatedButton(
          onPressed: canSubmit ? submit : null,
          child: Text(
            submitting.value ? context.l10n.processing : context.l10n.add,
          ),
        ),
      ],
    );
  }
}
