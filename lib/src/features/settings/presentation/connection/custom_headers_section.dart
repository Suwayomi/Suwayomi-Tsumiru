// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../features/auth/data/custom_headers_store.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/section_title.dart';

/// Connection-screen editor for generic custom HTTP headers.
///
/// Every entry is sent with each request to the Suwayomi server (GraphQL,
/// images, login, background workers). The motivating setup is a server
/// behind a Cloudflare Tunnel guarded by Zero Trust Access, which requires
/// `CF-Access-Client-Id` + `CF-Access-Client-Secret` on every request —
/// but any reverse-proxy header pair works.
class CustomHeadersSection extends HookConsumerWidget {
  const CustomHeadersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Preloaded in main() before the first frame; falls back to empty while
    // the secure-storage read is in flight.
    final headers =
        ref.watch(customHttpHeadersProvider).value ?? const {};
    final entries = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    Future<void> addOrEdit({String? existingName}) async {
      final result = await showDialog<({String name, String value})>(
        context: context,
        builder: (_) => _HeaderDialog(
          isEdit: existingName != null,
          initialName: existingName ?? '',
          initialValue: existingName == null
              ? ''
              : (headers[existingName] ?? ''),
          takenNames: headers.keys.toSet(),
          editingName: existingName,
        ),
      );
      if (result == null || result.name.isEmpty) return;
      if (existingName != null && existingName != result.name) {
        await ref.read(customHttpHeadersProvider.notifier).remove(existingName);
      }
      await ref
          .read(customHttpHeadersProvider.notifier)
          .put(result.name, result.value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.customHeaders),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            context.l10n.customHeadersDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              context.l10n.customHeaderEmpty,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        for (final entry in entries)
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: Text(entry.key),
            subtitle: Text(
              entry.value.isEmpty ? '—' : '••••••••',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => addOrEdit(existingName: entry.key),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => ref
                      .read(customHttpHeadersProvider.notifier)
                      .remove(entry.key),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () => addOrEdit(),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.l10n.customHeaderAdd),
          ),
        ),
      ],
    );
  }
}

class _HeaderDialog extends HookConsumerWidget {
  const _HeaderDialog({
    required this.isEdit,
    required this.initialName,
    required this.initialValue,
    required this.takenNames,
    required this.editingName,
  });

  final bool isEdit;
  final String initialName;
  final String initialValue;
  final Set<String> takenNames;
  final String? editingName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(text: initialName);
    final valueController = useTextEditingController(text: initialValue);
    final nameError = useState<String?>(null);

    void save() {
      final name = nameController.text.trim();
      if (validateCustomHeaderName(name) != null) {
        nameError.value = context.l10n.customHeaderNameInvalid;
        return;
      }
      if ((editingName == null || editingName != name) &&
          takenNames.contains(name)) {
        nameError.value = context.l10n.customHeaderExists;
        return;
      }
      Navigator.pop(context, (name: name, value: valueController.text));
    }

    return AlertDialog(
      title: Text(
        isEdit ? context.l10n.customHeaderName : context.l10n.customHeaderAdd,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.customHeaderName,
              hintText: 'X-Custom-Header',
              border: const OutlineInputBorder(),
              errorText: nameError.value,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: valueController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.customHeaderValue,
              hintText: '••••••••',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(onPressed: save, child: Text(context.l10n.save)),
      ],
    );
  }
}
