// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../network/graphql_errors.dart';
import 'diagnostics.dart';
import 'redact_tokens.dart';

/// Log failures caught by Riverpod, excluding connection errors; deduplicate per provider/error per session.
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
