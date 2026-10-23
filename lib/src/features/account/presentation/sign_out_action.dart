// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/app_utils.dart';
import '../../../utils/misc/toast/toast.dart';
import '../../../utils/motion/reduce_motion.dart';
import '../../../widgets/popup_widgets/pop_button.dart';
import '../../settings/presentation/connection/prompt_sign_in.dart';
import '../data/account_actions.dart';

/// Shared "Sign out" flow for the Connection page's Account card and the
/// More screen: the Account screen's confirmation dialog, then the account
/// sign-out, staying on Connection across the identity change.
Future<void> confirmAndSignOutAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.accountSignOut),
      content: Text(context.l10n.accountSignOutConfirmation),
      actions: [
        const PopButton(),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.accountSignOut),
        ),
      ],
    ),
    animationStyle: context.motionStyle,
  );
  if (confirmed != true || !context.mounted) return;
  await AppUtils.guard(
    ref.read(accountActionsProvider).signOut,
    ref.read(toastProvider),
  );
  stayOnConnectionAfterIdentityChange();
}
