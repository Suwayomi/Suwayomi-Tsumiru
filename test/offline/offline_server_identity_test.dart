import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';

void main() {
  group('serverIdentity', () {
    test('normalizes trailing paths and the effective port', () {
      expect(
        serverAddress(
          baseUrl: 'https://reader.example.test/path/',
          port: 4567,
          addPort: true,
        ),
        'https://reader.example.test:4567',
      );
    });

    test('uses the URL port when the port toggle is off', () {
      expect(
        serverAddress(
          baseUrl: 'http://reader.example.test:8080/',
          port: 4567,
          addPort: false,
        ),
        'http://reader.example.test:8080',
      );
    });

    test('makes implicit and explicit default ports identical', () {
      final implicit = serverAddress(
        baseUrl: 'https://reader.example.test',
        port: null,
        addPort: false,
      );
      final explicit = serverAddress(
        baseUrl: 'https://reader.example.test:443/',
        port: null,
        addPort: false,
      );
      expect(implicit, explicit);
      expect(implicit, 'https://reader.example.test:443');
    });
  });

  test('catalog is parked on another server and restored on return', () {
    const serverA = 'https://a.example.test:443';
    const serverB = 'https://b.example.test:443';

    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverA,
      ),
      isTrue,
    );
    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverB,
      ),
      isFalse,
    );
    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverA,
      ),
      isTrue,
    );
  });

  test('unstamped catalogs are trusted only when offline storage exists', () {
    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: null,
        currentServer: 'https://reader.example.test:443',
      ),
      isTrue,
    );
    expect(
      isOfflineCatalogActive(
        offlineEnabled: false,
        catalogServer: null,
        currentServer: 'https://reader.example.test:443',
      ),
      isFalse,
    );
  });

  test('creates a UUID v4 server identifier', () {
    final id = createServerInstanceId();
    expect(
      id,
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
  });
}
