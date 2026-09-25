// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'server_resolver.dart';

/// LAN discovery for the onboarding "Search my network" action.
///
/// Sweeps the device's Wi-Fi /24 subnet for a Suwayomi server in two steps:
/// a TCP connect probe on every host×port, then a real `aboutServer`
/// confirmation of each port that answered, so an open port belonging to
/// something else (a printer, a router) is never offered. The Wi-Fi-IP lookup,
/// the per-host ping and the confirmation are all injectable so the sweep logic
/// is unit-testable without a network.

/// The ports Suwayomi is commonly run on. 4567 is the default; 4568-4570 catch
/// a server moved off the default (which is what "Search my network" missed).
const List<int> kSuwayomiScanPorts = [4567, 4568, 4569, 4570];

/// One confirmed Suwayomi server found on the local network.
class DiscoveredServer {
  const DiscoveredServer({required this.url, this.name, this.version});

  /// Base URL, always `http://<ip>:<port>` for a discovered host.
  final String url;

  /// `aboutServer.name`, when the server reported one.
  final String? name;

  /// `aboutServer.version`, when the server reported one.
  final String? version;

  String get host => Uri.parse(url).host;

  int get port => Uri.parse(url).port;

  /// `host:port` without the scheme — what the picker shows.
  String get address => '$host:$port';
}

/// Confirms ONE answering `http://host:port` really is Suwayomi. Returns the
/// server with name/version carried through, or null when it is not Suwayomi.
typedef ServerConfirmer = Future<DiscoveredServer?> Function(String url);

/// Every host to probe for [ip]'s /24 subnet (`x.y.z.1` … `x.y.z.254`), plus
/// [ip] itself, de-duplicated and order-preserving.
List<String> subnetHosts(String ip) {
  final dot = ip.lastIndexOf('.');
  if (dot < 0) return [ip];
  final subnet = ip.substring(0, dot);
  return <String>{ip, for (var i = 1; i < 255; i++) '$subnet.$i'}.toList();
}

/// Scans the Wi-Fi subnet for Suwayomi servers on [ports]. Every host×port is
/// TCP-pinged in concurrent batches; each pair that answers is then confirmed
/// by [confirm] (default: a real [probeServer] against `http://host:port`),
/// with at most 8 confirmations in flight. Returns the confirmed servers sorted
/// by IP, then port. Empty when there is no Wi-Fi IP or nothing answers.
///
/// [batchSize] is 128: the full /24 × 4 ports is 1016 probes, so 8 batches at a
/// 1 s timeout put the worst case near 8 s while keeping the in-flight socket
/// count well under the mobile fd limit.
Future<List<DiscoveredServer>> discoverServersOnLan({
  Future<String?> Function()? wifiIp,
  Future<bool> Function(String host, int port)? ping,
  ServerConfirmer? confirm,
  List<int> ports = kSuwayomiScanPorts,
  int batchSize = 128,
}) async {
  final ip = await (wifiIp ?? localLanIp)();
  if (ip == null || ip.isEmpty) return const [];

  final doPing = ping ?? _ping;
  final targets = <(String, int)>[
    for (final host in subnetHosts(ip))
      for (final port in ports) (host, port),
  ];

  // Step 1: which host:port pairs accept a TCP connection at all.
  final open = <String>[];
  for (var start = 0; start < targets.length; start += batchSize) {
    final end = (start + batchSize) < targets.length
        ? start + batchSize
        : targets.length;
    final batch = targets.sublist(start, end);
    final results = await Future.wait(
      batch.map(
        (t) async =>
            (await doPing(t.$1, t.$2)) ? 'http://${t.$1}:${t.$2}' : null,
      ),
    );
    open.addAll(results.whereType<String>());
  }
  if (open.isEmpty) return const [];

  // Step 2: keep only the ones that answer like Suwayomi.
  final doConfirm = confirm ?? _confirmSuwayomi;
  final found = (await _mapConcurrent(
    open,
    8,
    doConfirm,
  )).whereType<DiscoveredServer>().toList();
  found.sort(_byHostThenPort);
  return found;
}

/// Runs [run] over [items] with at most [limit] in flight, preserving order.
Future<List<T>> _mapConcurrent<A, T>(
  List<A> items,
  int limit,
  Future<T> Function(A item) run,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await run(items[i]);
    }
  }

  await Future.wait([
    for (var i = 0; i < limit && i < items.length; i++) worker(),
  ]);
  return results.cast<T>();
}

/// The default [ServerConfirmer]: a real Suwayomi `aboutServer` probe.
Future<DiscoveredServer?> _confirmSuwayomi(String url) async {
  final client = http.Client();
  try {
    final result = await probeServer(url, client: client);
    if (!result.confirmed) return null;
    return DiscoveredServer(
      url: url,
      name: result.serverName,
      version: result.serverVersion,
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Numeric order within a /24, so `.2` sorts before `.10`; falls back to string
/// order for anything that is not an IPv4 host.
int _byHostThenPort(DiscoveredServer a, DiscoveredServer b) {
  final ao = a.host.split('.');
  final bo = b.host.split('.');
  if (ao.length == 4 && bo.length == 4) {
    for (var i = 0; i < 4; i++) {
      final c = (int.tryParse(ao[i]) ?? 0).compareTo(int.tryParse(bo[i]) ?? 0);
      if (c != 0) return c;
    }
  } else {
    final c = a.host.compareTo(b.host);
    if (c != 0) return c;
  }
  return a.port.compareTo(b.port);
}

Future<bool> _ping(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 1000),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// The device's private LAN IPv4, found WITHOUT any runtime permission via
/// [NetworkInterface.list]. The old default — `network_info_plus.getWifiIP()` —
/// can return null on a fresh install that hasn't been granted location access,
/// so the subnet scan never ran and "Search my network" found nothing. Falls
/// back to the Wi-Fi plugin if no private IPv4 interface is found.
Future<String?> localLanIp() async {
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (_isPrivateV4(addr.address)) return addr.address;
      }
    }
  } catch (_) {
    // Fall through to the plugin.
  }
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null;
  }
}

/// RFC 1918 private IPv4: 10/8, 172.16/12, 192.168/16.
bool _isPrivateV4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
