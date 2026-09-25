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
  group('subnetHosts', () {
    test('generates the /24 sweep including the ip, de-duped', () {
      final hosts = subnetHosts('192.168.1.50');
      expect(hosts, contains('192.168.1.1'));
      expect(hosts, contains('192.168.1.254'));
      expect(hosts.first, '192.168.1.50'); // ip probed first
      expect(hosts.where((h) => h == '192.168.1.50').length, 1); // de-duped
      expect(hosts.length, 254);
    });

    test('malformed ip → just itself', () {
      expect(subnetHosts('not-an-ip'), ['not-an-ip']);
    });
  });

  group('discoverServersOnLan', () {
    test('finds a server on 4568 when 4567 is closed', () async {
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
    });

    test('an open port that is not Suwayomi is not reported', () async {
      final found = await discoverServersOnLan(
        wifiIp: () async => '192.168.1.50',
        // A printer with 4567 open, but confirm rejects it.
        ping: (host, port) async => host == '192.168.1.9' && port == 4567,
        confirm: _confirmer(const {}),
      );
      expect(found, isEmpty);
    });

    test('several responders come back sorted by IP then port', () async {
      final found = await discoverServersOnLan(
        wifiIp: () async => '192.168.1.50',
        ping: (host, port) async =>
            (host == '192.168.1.30' && port == 4569) ||
            (host == '192.168.1.30' && port == 4567) ||
            (host == '192.168.1.7' && port == 4570) ||
            (host == '192.168.1.100' && port == 4568),
        confirm: _confirmer({
          for (final url in const [
            'http://192.168.1.30:4569',
            'http://192.168.1.30:4567',
            'http://192.168.1.7:4570',
            'http://192.168.1.100:4568',
          ])
            url: DiscoveredServer(url: url),
        }),
      );
      expect(found.map((s) => s.url).toList(), [
        'http://192.168.1.7:4570',
        'http://192.168.1.30:4567',
        'http://192.168.1.30:4569',
        'http://192.168.1.100:4568',
      ]);
    });

    test('no Wi-Fi IP → empty list', () async {
      expect(await discoverServersOnLan(wifiIp: () async => null), isEmpty);
    });

    test('nothing responds → empty list', () async {
      final found = await discoverServersOnLan(
        wifiIp: () async => '192.168.1.50',
        ping: (_, _) async => false,
      );
      expect(found, isEmpty);
    });

    test('probes every configured port on each host', () async {
      final probed = <String>{};
      await discoverServersOnLan(
        wifiIp: () async => '192.168.1.50',
        ping: (host, port) async {
          probed.add('$host:$port');
          return false;
        },
      );
      expect(probed, hasLength(254 * kSuwayomiScanPorts.length));
      for (final port in kSuwayomiScanPorts) {
        expect(probed, contains('192.168.1.4:$port'));
      }
    });
  });
}
