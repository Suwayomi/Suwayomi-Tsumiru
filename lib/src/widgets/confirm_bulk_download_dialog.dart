// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../utils/extensions/custom_extensions.dart';

/// Above this many chapters, a bulk download asks for confirmation first.
const int kBulkDownloadConfirmThreshold = 20;

/// Confirms a large bulk download before it starts, so a stray tap can't
/// silently queue hundreds of chapters (the keep-offline accident). Returns
/// true only if the user confirms.
///
/// [summary] describes the target in user terms — e.g. "12 series" or
/// "45 chapters". [toDevice] picks device-vs-server wording and icon (and is
/// why the device case warns about storage — that's the one that bites).
Future<bool> confirmBulkDownload(
  BuildContext context, {
  required String summary,
  required bool toDevice,
  String? downloadDescription,
}) async {
  final cs = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            toDevice ? Icons.save_alt_rounded : Icons.cloud_download_outlined,
            color: cs.primary,
          ),
          title: Text(
            toDevice
                ? 'Keep $summary on this device?'
                : 'Download $summary to the server?',
          ),
          content: Text(
            downloadDescription ??
                (toDevice
                    ? 'Every chapter of $summary will download to this device and '
                          'stay in sync as you read. This can use a lot of storage.'
                    : 'Every chapter of $summary will be queued for download on '
                          'the server.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download'),
            ),
          ],
        ),
      ) ??
      false;
}
