// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../network/graphql_errors.dart';
import 'diagnostics.dart';
import 'redact_tokens.dart';

/// Writes provider failures to the debug log.
///
/// A provider error is caught by Riverpod and shown in place (an error view in
/// a list, a snackbar…), so it never reaches `FlutterError.onError` and the
/// debug log had no trace of it — only its message on screen, with no stack.
///
/// Connection errors are skipped: they are the expected outcome of every read
/// while the server is unreachable. Each provider/error pair is logged once
/// per session, since Riverpod retries failing providers and a rebuild loop
/// would otherwise flood the log.
final class ProviderFailureLogger extends ProviderObserver {
  ProviderFailureLogger({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _logged = <String>{};

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (isConnectionError(error)) return;
    final provider = context.provider;
    final name = provider.name ?? provider.runtimeType.toString();
    final argument = provider.argument;
    final label = argument == null ? name : '$name($argument)';
    if (!_logged.add('$label|${error.runtimeType}|$error')) return;
    recordDiagnostic(
      redactTokens(
        '[${_now().toIso8601String()}] provider-failed: $label\n'
        '${error.runtimeType}: $error\n$stackTrace\n\n',
      ),
    );
  }
}
