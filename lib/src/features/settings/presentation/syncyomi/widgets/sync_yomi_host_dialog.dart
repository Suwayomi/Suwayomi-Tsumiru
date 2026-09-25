import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/async_buttons/async_text_button.dart';
import '../domain/sync_yomi.dart';

/// TextFieldDialog with a validator: a bad host must not be saved, and the
/// user should see why without losing what they typed.
class SyncYomiHostDialog extends HookConsumerWidget {
  const SyncYomiHostDialog({super.key, this.value, required this.onSave});

  final String? value;
  final Future<bool> Function(String) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController(text: value);
    final error = useState<String?>(null);
    return AlertDialog(
      title: Text(context.l10n.syncYomiHost),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: context.l10n.syncYomiHostHint,
          border: const OutlineInputBorder(),
          errorText: error.value,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        AsyncTextButton(
          onPressed: () async {
            final host = normaliseSyncYomiHost(controller.text);
            if (host == null) {
              error.value = context.l10n.syncYomiHostInvalid;
              return;
            }
            final saved = await onSave(host);
            if (saved && context.mounted) Navigator.pop(context);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
