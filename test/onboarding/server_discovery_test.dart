// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Unit tests for LAN server discovery (the "Search my network" sweep).

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/onboarding/data/server_discovery.dart';

/// A [ServerConfirmer] that confirms exactly the URLs in [known], tagging each
/// with a name/version so the caller can tell them apart.
ServerConfirmer _confirmer(Map<String, DiscoveredServer> known) =>
    (url) async => known[url];

void main() {
  test('sweeps the subnet, finds 4568 and rejects non-Suwayomi', () async {
    final hosts = subnetHosts('192.168.1.50');
    expect(hosts, contains('192.168.1.1'));
    expect(hosts, contains('192.168.1.254'));
    expect(hosts.first, '192.168.1.50'); // ip probed first
    expect(hosts.where((h) => h == '192.168.1.50').length, 1); // de-duped
    expect(hosts.length, 254);

    final found = await discoverServersOnLan(
      wifiIp: () async => '192.168.1.50',
      ping: (host, port) async => host == '192.168.1.7' && port == 4568,
      confirm: _confirmer({
        'http://192.168.1.7:4568': const DiscoveredServer(
          url: 'http://192.168.1.7:4568',
          name: 'Suwayomi-Server',
          version: '2.3.2162',
        ),
      }),
    );
    expect(found, hasLength(1));
    expect(found.single.url, 'http://192.168.1.7:4568');
    expect(found.single.name, 'Suwayomi-Server');
    expect(found.single.version, '2.3.2162');
    expect(found.single.address, '192.168.1.7:4568');

    // An open port that is not Suwayomi is not reported.
    final notSuwayomi = await discoverServersOnLan(
      wifiIp: () async => '192.168.1.50',
      ping: (host, port) async => host == '192.168.1.9' && port == 4567,
      confirm: _confirmer(const {}),
    );
    expect(notSuwayomi, isEmpty);
  });
}
