import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';

void main() {
  group('parsePercentageTolerance', () {
    test('zero and negatives save as the server minimum', () {
      expect(parsePercentageTolerance('0'), 1e-15);
      expect(parsePercentageTolerance('0.0'), 1e-15);
      expect(parsePercentageTolerance('-0.5'), 1e-15);
    });

    test('keeps a decimal in range', () {
      expect(parsePercentageTolerance('0.1'), 0.1);
      expect(parsePercentageTolerance('1'), 1);
      expect(parsePercentageTolerance('1e-15'), 1e-15);
    });

    test('rejects non-numbers and values above 1', () {
      expect(parsePercentageTolerance('abc'), isNull);
      expect(parsePercentageTolerance(''), isNull);
      expect(parsePercentageTolerance('1.5'), isNull);
    });
  });

  group('formatPercentageTolerance', () {
    test('shows up to two decimal places', () {
      expect(formatPercentageTolerance(0.1), '0.1');
      expect(formatPercentageTolerance(0.5), '0.5');
      expect(formatPercentageTolerance(0.25), '0.25');
      expect(formatPercentageTolerance(1), '1');
    });

    test('shows anything below 0.005 as zero', () {
      expect(formatPercentageTolerance(1e-15), '0');
      expect(formatPercentageTolerance(0.004), '0');
    });
  });

  group('formatPercentageToleranceInput', () {
    test('prefills the exact stored value', () {
      expect(formatPercentageToleranceInput(0.005), '0.005');
      expect(formatPercentageToleranceInput(0.1), '0.1');
      expect(formatPercentageToleranceInput(1e-15), '0');
    });
  });
}
