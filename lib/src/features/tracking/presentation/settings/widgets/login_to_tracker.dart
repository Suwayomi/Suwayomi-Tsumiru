// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../data/graphql/__generated__/query.graphql.dart';
import '../../../data/tracker_repository.dart';
import '../../../domain/tracker_oauth_helpers.dart';
import '../../login/tracker_credentials_sheet.dart';

/// Opens the appropriate login UI for [tracker]:
/// - OAuth tracker (`tracker.authUrl != null`): opens the tracker's auth URL
///   in the external browser. The OS will return the OAuth callback via the
///   `tsumiru://tracker-oauth` deep link, handled by the listener set up in
///   `main.dart`.
/// - Credential tracker (`tracker.authUrl == null`): a bottom-sheet with
///   username + password fields.
///
/// On credentials success, invalidates [trackersProvider] and shows a success
/// toast. OAuth success is handled asynchronously by the deep-link listener.
Future<void> loginToTracker(
  WidgetRef ref,
  Fragment$TrackerDto tracker,
) async {
  final context = ref.context;
  if (!context.mounted) return;

  final toast = ref.read(toastProvider);
  final repo = ref.read(trackerRepositoryProvider);

  if (tracker.authUrl != null) {
    // Deep-link OAuth flow: build the full auth URL with state, then open it
    // in the external browser. The OS hands the callback back via
    // tsumiru://tracker-oauth, which is handled in main.dart.
    final redirectUrl = kIsWeb
        ? Uri.base.resolve('/tracker-oauth').toString()
        : 'tsumiru://tracker-oauth';
    final builtUrl = buildTrackerAuthUrl(
      authUrl: tracker.authUrl!,
      trackerId: tracker.id,
      trackerName: tracker.name,
      redirectUrl: redirectUrl,
    );
    await launchUrlInWeb(context, builtUrl, toast);
  } else {
    // Credentials flow
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => TrackerCredentialsSheet(
        trackerName: tracker.name,
        onSubmit: (username, password) async {
          Navigator.of(ctx).pop();
          try {
            await repo.loginCredentials(
              trackerId: tracker.id,
              username: username,
              password: password,
            );
            if (context.mounted) {
              ref.invalidate(trackersProvider);
              toast?.show(context.l10n.trackerLoginSuccess(tracker.name));
            }
          } catch (e) {
            toast?.showError(e.toString());
          }
        },
      ),
    );
  }
}
