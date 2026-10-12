// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';

class ReaderChapterGapWarning extends StatelessWidget {
  const ReaderChapterGapWarning({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          color: context.theme.colorScheme.error,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(context.l10n.readerChapterGapWarning(count))),
      ],
    );
  }
}

Future<bool> confirmReaderChapterGap(BuildContext context, int count) async {
  if (count <= 0) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: ReaderChapterGapWarning(count: count),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.readerChapterGapContinue),
            ),
          ],
        ),
      ) ??
      false;
}
