import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_status.dart';

void main() {
  group('formatServerHost', () {
    test('strips scheme and appends port when toggle on', () {
      expect(formatServerHost('http://myserver.local', 4567, true),
          'myserver.local:4567');
    });
    test('omits port when toggle off', () {
      expect(formatServerHost('http://myserver.local', 4567, false),
          'myserver.local');
    });
    test('https scheme and explicit port', () {
      expect(formatServerHost('https://manga.example.com', 443, true),
          'manga.example.com:443');
    });
    test('strips trailing slash', () {
      expect(formatServerHost('http://192.168.2.5/', 4567, true),
          '192.168.2.5:4567');
    });
    test('blank or null url returns empty', () {
      expect(formatServerHost(null, 4567, true), '');
      expect(formatServerHost('', 4567, true), '');
    });
    test('toggle on but null port omits port', () {
      expect(formatServerHost('http://host', null, true), 'host');
    });
  });

  group('connectionAuthStatus', () {
    test('needsReauth wins even with a configured auth type', () {
      expect(connectionAuthStatus(AuthType.basic, true),
          ConnectionAuthStatus.signInNeeded);
      expect(connectionAuthStatus(AuthType.none, true),
          ConnectionAuthStatus.signInNeeded);
    });
    test('none or null is noAuth', () {
      expect(connectionAuthStatus(AuthType.none, false),
          ConnectionAuthStatus.noAuth);
      expect(connectionAuthStatus(null, false),
          ConnectionAuthStatus.noAuth);
    });
    test('configured auth type is signedIn', () {
      expect(connectionAuthStatus(AuthType.basic, false),
          ConnectionAuthStatus.signedIn);
      expect(connectionAuthStatus(AuthType.simpleLogin, false),
          ConnectionAuthStatus.signedIn);
      expect(connectionAuthStatus(AuthType.uiLogin, false),
          ConnectionAuthStatus.signedIn);
    });
  });
}
