// Copied debug dump: client name/version/platform, server name/version/
// channel/build time, and the web interface flavour/version when reported.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/about/presentation/about/widget/debug_information_tile.dart';

void main() {
  test('debug text carries client, server and web interface lines', () {
    expect(
      buildDebugInfoText(
        clientName: 'Tsumiru',
        clientVersion: '0.7.1',
        platform: 'android 15',
        serverName: 'Suwayomi-Server',
        serverVersion: 'v2.4.2366',
        serverChannel: 'STABLE',
        serverBuildTime: 'Jan 5, 2026',
        webUiFlavor: 'STABLE',
        webUiVersion: 'r3518',
      ),
      'Client: Tsumiru v0.7.1 (android 15)\n'
      'Server: Suwayomi-Server v2.4.2366 (STABLE, build time Jan 5, 2026)\n'
      'Web interface: STABLE r3518',
    );
    expect(
      buildDebugInfoText(
        clientName: 'Tsumiru',
        clientVersion: '0.7.1',
        platform: 'web',
        serverName: 'Suwayomi-Server',
        serverVersion: 'v2.4.2366',
        serverChannel: 'STABLE',
        serverBuildTime: 'Jan 5, 2026',
      ),
      'Client: Tsumiru v0.7.1 (web)\n'
      'Server: Suwayomi-Server v2.4.2366 (STABLE, build time Jan 5, 2026)',
    );
  });
}
