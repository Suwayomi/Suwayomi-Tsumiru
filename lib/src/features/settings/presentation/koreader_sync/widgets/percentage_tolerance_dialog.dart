// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../data/koreader_sync_repository.dart';
import '../domain/koreader_sync_domain.dart';

class PercentageToleranceDialog extends HookConsumerWidget {
  const PercentageToleranceDialog({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final controller = useTextEditingController(
      text: formatPercentageToleranceInput(value),
    );
    final busy = useState(false);

    Future<void> save() async {
      if (!(formKey.currentState?.validate()).ifNull()) return;
      final parsed = parsePercentageTolerance(controller.text);
      if (parsed == null) return;
      busy.value = true;
      try {
        final saved = await AppUtils.guard(
          () => ref
              .read(koreaderSyncRepositoryProvider)
              .updatePercentageTolerance(parsed),
          ref.read(toastProvider),
        );
        if (!context.mounted) return;
        if (saved == true) Navigator.pop(context);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return AlertDialog(
      title: Text(l10n.koreaderSyncPercentageTolerance),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.koreaderSyncPercentageToleranceDescription),
            TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => parsePercentageTolerance(v ?? '') == null
                  ? l10n.koreaderSyncPercentageToleranceInvalid
                  : null,
              onFieldSubmitted: (_) {
                if (!busy.value) save();
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: busy.value ? null : save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
