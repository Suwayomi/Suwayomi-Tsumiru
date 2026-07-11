// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';

const kTsumiruServerIdMetaKey = 'tsumiru_server_instance_id';

String serverAddress({
  required String? baseUrl,
  required int? port,
  required bool addPort,
}) {
  final raw = Endpoints.baseApi(
    baseUrl: baseUrl ?? DBKeys.serverUrl.initial as String,
    port: port,
    addPort: addPort,
    appendApiToUrl: false,
  );
  final uri = Uri.parse(raw);
  final effectivePort = uri.hasPort
      ? uri.port
      : uri.scheme == 'https'
          ? 443
          : 80;
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme.toLowerCase()}://$host:$effectivePort';
}

String serverMismatchKey(String catalogServer, String currentServer) =>
    '$catalogServer\n$currentServer';

String createServerInstanceId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

bool isOfflineCatalogActive({
  required bool offlineEnabled,
  required String? catalogServer,
  required String currentServer,
}) =>
    offlineEnabled && (catalogServer == null || catalogServer == currentServer);
