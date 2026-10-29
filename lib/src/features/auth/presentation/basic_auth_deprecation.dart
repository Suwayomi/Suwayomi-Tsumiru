// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../data/basic_auth_deprecation.dart';

Future<void> basicAuthDeprecationDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.basicAuthDeprecationTitle),
      content: Text(context.l10n.basicAuthDeprecationBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    ),
    animationStyle: context.motionStyle,
  );
}

Future<void> maybeShowBasicAuthDeprecation({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  if (!context.mounted) return;
  if (ref.read(authTypeKeyProvider) != AuthType.basic) return;
  if (Navigator.of(context, rootNavigator: true).canPop()) return;
  final address = ref.read(currentServerAddressProvider);
  final uri = Uri.tryParse(address);
  if (uri == null || uri.host.isEmpty) return;
  final endpoint = uri
      .replace(userInfo: '', query: '', fragment: '')
      .toString();
  final notices = ref.read(basicAuthDeprecationLastShownProvider.notifier);
  if (!notices.isDue(endpoint, DateTime.now())) return;
  final shown = basicAuthDeprecationDialog(context: context);
  notices.markShown(endpoint, DateTime.now());
  await shown;
}
