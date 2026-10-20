import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/domain/sync_yomi.dart';

void main() {
  group('normaliseSyncYomiHost', () {
    test('keeps valid origins, trimming whitespace and trailing slashes', () {
      expect(
        normaliseSyncYomiHost('https://syncyomi.example.com'),
        'https://syncyomi.example.com',
      );
      expect(
        normaliseSyncYomiHost('  https://syncyomi.example.com///  '),
        'https://syncyomi.example.com',
      );
      expect(
        normaliseSyncYomiHost('http://host:8080/syncyomi/'),
        'http://host:8080/syncyomi',
      );
      expect(normaliseSyncYomiHost('https://h/syncyomi'), 'https://h/syncyomi');

      // Rejects anything that is not a plain http(s) origin or path.
      for (final bad in [
        'syncyomi.example.com',
        'ftp://syncyomi.example.com',
        'https://',
        'https://syncyomi.example.com/?token=x',
        'https://h/#x',
        '   ',
      ]) {
        expect(normaliseSyncYomiHost(bad), isNull, reason: bad);
      }
    });
  });
}
