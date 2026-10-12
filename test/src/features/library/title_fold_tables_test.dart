import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/title_fold.dart';
import 'package:unorm_dart/unorm_dart.dart';

void expectFold(String input, String expected) {
  expect(
    nfkc(input),
    expected,
    reason: 'unorm_dart disagrees with the expectation',
  );
  expect(foldTitleCompat(input), expected);
}

void main() {
  test('every BMP character folds as unorm_dart NFKC folds it alone', () {
    for (var c = 0; c <= 0xFFFF; c++) {
      if (c >= 0xD800 && c <= 0xDFFF) continue;
      final ch = String.fromCharCode(c);
      expect(
        foldTitleCompat(ch),
        nfkc(ch),
        reason: 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      );
    }
  });

  test('compatibility characters map as NFKC does', () {
    expectFold('ﬁ', 'fi');
    expectFold('①', '1');
    expectFold('Ⅱ', 'II');
    expectFold('ＢＥＲＳＥＲＫ', 'BERSERK');
  });

  test('marks compose onto the preceding letter, stacked marks included', () {
    expectFold('é', 'é');
    expectFold('ｶﾞ', 'ガ');
    expectFold('Ậ', 'Ậ');
    expectFold('ά', 'ά');
    expectFold('й', 'й');
    expectFold('が', 'が');
  });
}
