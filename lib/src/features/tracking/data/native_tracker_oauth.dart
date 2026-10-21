// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/pending_tracker_oauth_store.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import '../domain/tracker_oauth_helpers.dart';
import '../domain/tracker_oauth_origin.dart';
import 'tracker_repository.dart';

enum TrackerOAuthOutcome { ignored, rejected, failed, succeeded }

enum TrackerOAuthBeginOutcome {
  started,
  superseded,
  invalidSession,
  saveFailed,
  failed,
}

const nativeTrackerOAuthRedirect = 'tsumiru://tracker-oauth';
const _lifetime = Duration(minutes: 10);

class _Pending {
  _Pending({
    required this.nonce,
    required this.trackerId,
    required this.redirect,
    required this.issuedAt,
    required this.expiresAt,
    required this.origin,
  });
  final String nonce;
  final int trackerId;
  final String redirect;
  final int issuedAt;
  final int expiresAt;
  final String origin;

  String encode() => jsonEncode({
    'nonce': nonce,
    'trackerId': trackerId,
    'redirectUrl': redirect,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'origin': origin,
  });

  static _Pending? decode(String? raw) {
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['nonce'] is! String ||
          value['trackerId'] is! int ||
          value['redirectUrl'] is! String ||
          value['issuedAt'] is! int ||
          value['expiresAt'] is! int ||
          value['origin'] is! String) {
        return null;
      }
      return _Pending(
        nonce: value['nonce'],
        trackerId: value['trackerId'],
        redirect: value['redirectUrl'],
        issuedAt: value['issuedAt'],
        expiresAt: value['expiresAt'],
        origin: value['origin'],
      );
    } catch (_) {
      return null;
    }
  }
}

class NativeTrackerOAuth {
  NativeTrackerOAuth({
    required this.pending,
    required this.captureSession,
    required this.readOrigin,
    required this.loginOAuth,
    required this.onSuccess,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final PendingTrackerOAuthStore pending;
  final bool Function() Function() captureSession;
  final Future<String?> Function(bool Function() current) readOrigin;
  final Future<void> Function(int trackerId, String callback) loginOAuth;
  final void Function() onSuccess;
  final DateTime Function() now;

  Future<void> _clearOwn(String nonce) async {
    await pending.clearIfNonce(nonce);
  }

  Future<TrackerOAuthBeginOutcome> begin({
    required String authUrl,
    required int trackerId,
    required String trackerName,
    required Future<void> Function(String url) launch,
  }) async {
    final current = captureSession();
    if (!current()) return TrackerOAuthBeginOutcome.invalidSession;
    String? nonce;
    try {
      final origin = await readOrigin(current);
      if (!current() || origin == null) {
        return TrackerOAuthBeginOutcome.invalidSession;
      }
      final random = Random.secure();
      nonce = base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final issuedAt = now().millisecondsSinceEpoch;
      final request = _Pending(
        nonce: nonce,
        trackerId: trackerId,
        redirect: nativeTrackerOAuthRedirect,
        issuedAt: issuedAt,
        expiresAt: issuedAt + _lifetime.inMilliseconds,
        origin: origin,
      );
      final saved = await pending.replace(request.encode());
      if (!current()) {
        await _clearOwn(nonce);
        return TrackerOAuthBeginOutcome.invalidSession;
      }
      if (!saved) {
        await _clearOwn(nonce);
        return TrackerOAuthBeginOutcome.saveFailed;
      }
      final owner = _Pending.decode(await pending.read())?.nonce;
      if (!current()) {
        await _clearOwn(nonce);
        return TrackerOAuthBeginOutcome.invalidSession;
      }
      if (owner != nonce) return TrackerOAuthBeginOutcome.superseded;
      final url = buildTrackerAuthUrl(
        authUrl: authUrl,
        trackerId: trackerId,
        trackerName: trackerName,
        redirectUrl: nativeTrackerOAuthRedirect,
        nonce: nonce,
      );
      await launch(url);
      if (!current()) {
        await _clearOwn(nonce);
        return TrackerOAuthBeginOutcome.invalidSession;
      }
      return TrackerOAuthBeginOutcome.started;
    } catch (_) {
      if (nonce != null) await _clearOwn(nonce);
      return TrackerOAuthBeginOutcome.failed;
    }
  }

  Future<TrackerOAuthOutcome> handleCallback(Uri uri) async {
    if (uri.scheme != 'tsumiru' || uri.host != 'tracker-oauth') {
      return TrackerOAuthOutcome.ignored;
    }
    if (uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return TrackerOAuthOutcome.rejected;
    }
    final current = captureSession();
    if (!current()) return TrackerOAuthOutcome.rejected;
    try {
      final states = uri.queryParametersAll['state'];
      if (states == null || states.length != 1) {
        return TrackerOAuthOutcome.rejected;
      }
      final state = jsonDecode(states.single);
      if (state is! Map<String, dynamic>) return TrackerOAuthOutcome.rejected;
      final origin = await readOrigin(current);
      if (!current() || origin == null) return TrackerOAuthOutcome.rejected;
      final encoded = await pending.read();
      if (!current()) return TrackerOAuthOutcome.rejected;
      final request = _Pending.decode(encoded);
      final time = now().millisecondsSinceEpoch;
      if (request == null ||
          state['nonce'] != request.nonce ||
          state['trackerId'] != request.trackerId ||
          state['redirectUrl'] != nativeTrackerOAuthRedirect ||
          request.redirect != nativeTrackerOAuthRedirect ||
          request.origin != origin ||
          request.issuedAt > time ||
          request.expiresAt <= time ||
          request.expiresAt - request.issuedAt != _lifetime.inMilliseconds) {
        return TrackerOAuthOutcome.rejected;
      }
      final saved = await pending.claim(encoded!);
      if (!saved || !current()) return TrackerOAuthOutcome.rejected;
      await loginOAuth(request.trackerId, uri.toString());
      if (!current()) return TrackerOAuthOutcome.rejected;
      onSuccess();
      return TrackerOAuthOutcome.succeeded;
    } catch (_) {
      return current()
          ? TrackerOAuthOutcome.failed
          : TrackerOAuthOutcome.rejected;
    }
  }
}

final nativeTrackerOAuthProvider = Provider<NativeTrackerOAuth>((ref) {
  final pending = ref.watch(pendingTrackerOAuthStoreProvider);
  final credentials = ref.watch(authCredentialsStoreProvider.notifier);
  final repository = ref.watch(trackerRepositoryProvider);
  return NativeTrackerOAuth(
    pending: pending,
    captureSession: credentials.captureSession,
    readOrigin: (current) async {
      final state = await ref.read(authCredentialsStoreProvider.future);
      if (!current()) return null;
      final mode = ref.read(authTypeKeyProvider) ?? AuthType.none;
      final external = ref.read(serverExternalUrlProvider);
      final server = external == null || external.trim().isEmpty
          ? ref.read(serverUrlProvider)
          : external;
      return trackerOAuthOrigin(
        mode: mode,
        configuredServer: server,
        username: ref.read(authUsernameProvider),
        binding: state.accountBinding,
      );
    },
    loginOAuth: (trackerId, callback) =>
        repository.loginOAuth(trackerId: trackerId, callbackUrl: callback),
    onSuccess: () => ref.invalidate(trackersProvider),
  );
});
