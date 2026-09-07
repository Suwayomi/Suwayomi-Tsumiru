import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';

void main() {
  for (final userId in <int?>[null, 2]) {
    test(
      'restores account ownership only with its complete token pair: $userId',
      () {
        final binding = AccountBinding(
          address: 'https://server.example:443',
          userId: userId,
          username: 'reader',
          catalogId: 'catalog-a',
        );
        final encoded = binding.encode(
          accessToken: 'access-a',
          refreshToken: 'refresh-a',
        );
        final restored = AccountBinding.decode(
          encoded,
          accessToken: 'access-a',
          refreshToken: 'refresh-a',
        );
        expect(restored?.address, 'https://server.example:443');
        expect(restored?.userId, userId);
        expect(restored?.catalogId, 'catalog-a');
        expect(restored?.username, 'reader');
        for (final pair in [
          ('access-b', 'refresh-a'),
          ('access-a', 'refresh-b'),
          (null, 'refresh-a'),
          ('access-a', null),
        ]) {
          expect(
            AccountBinding.decode(
              encoded,
              accessToken: pair.$1,
              refreshToken: pair.$2,
            ),
            isNull,
          );
        }
      },
    );
  }
  test('rejects malformed ownership and unsafe catalogue paths', () {
    for (final raw in [
      null,
      '',
      '{}',
      '[]',
      '{"address":2}',
      '{"address":"server","username":"reader","catalogId":"../other","userId":2,"accessToken":"a","refreshToken":"r"}',
      '{"address":"server","username":"reader","catalogId":"safe","userId":0,"accessToken":"a","refreshToken":"r"}',
    ]) {
      expect(
        AccountBinding.decode(raw, accessToken: 'a', refreshToken: 'r'),
        isNull,
      );
    }
  });
}
