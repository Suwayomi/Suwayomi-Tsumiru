import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

void main() {
  group('selectServerUrl', () {
    const external = 'https://suwayomi.example.com';
    const lan = 'http://192.168.1.100:4567';

    test('uses the external URL when no LAN URL is configured', () async {
      final selected = await selectServerUrl(
        externalUrl: external,
        lanUrl: null,
        isReachable: (_) async => throw StateError('should not probe'),
      );

      expect(selected, external);
    });

    test('prefers a reachable LAN URL', () async {
      final selected = await selectServerUrl(
        externalUrl: external,
        lanUrl: lan,
        isReachable: (url) async => url == lan,
      );

      expect(selected, lan);
    });

    test(
      'falls back to the external URL when the LAN URL is unavailable',
      () async {
        final selected = await selectServerUrl(
          externalUrl: external,
          lanUrl: lan,
          isReachable: (_) async => false,
        );

        expect(selected, external);
      },
    );

    test('normalises a LAN URL before probing it', () async {
      var probed = '';
      await selectServerUrl(
        externalUrl: external,
        lanUrl: '$lan/',
        isReachable: (url) async {
          probed = url;
          return false;
        },
      );

      expect(probed, lan);
    });
  });
}
