// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../../../constants/enum.dart';
import '../../account/domain/account_binding.dart';

String? trackerOAuthOrigin({
  required AuthType mode,
  required String? configuredServer,
  required String? username,
  AccountBinding? binding,
}) {
  if (mode == AuthType.uiLogin && binding != null) {
    final account = binding.userId ?? binding.username.trim();
    if (binding.catalogId.isEmpty || account == '') return null;
    return jsonEncode([mode.name, binding.catalogId, account]);
  }
  final uri = Uri.tryParse(configuredServer?.trim() ?? '');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  final server = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.normalizePath().path,
  ).toString();
  final account = mode == AuthType.none ? null : username?.trim();
  if (mode != AuthType.none && (account == null || account.isEmpty)) {
    return null;
  }
  return jsonEncode([mode.name, server, account]);
}
