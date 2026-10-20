import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';

void main() {
  group('parsePercentageTolerance', () {
    test('accepts in-range values and floors zero and negatives', () {
      expect(parsePercentageTolerance('0'), 1e-15);
      expect(parsePercentageTolerance('0.0'), 1e-15);
      expect(parsePercentageTolerance('-0.5'), 1e-15);
      expect(parsePercentageTolerance('0.1'), 0.1);
      expect(parsePercentageTolerance('1'), 1);
      expect(parsePercentageTolerance('1e-15'), 1e-15);
      expect(parsePercentageTolerance('abc'), isNull);
      expect(parsePercentageTolerance(''), isNull);
      expect(parsePercentageTolerance('1.5'), isNull);
    });
  });

  group('formatPercentageTolerance', () {
    test('shows up to two decimals, with tiny values as zero', () {
      expect(formatPercentageTolerance(0.1), '0.1');
      expect(formatPercentageTolerance(0.5), '0.5');
      expect(formatPercentageTolerance(0.25), '0.25');
      expect(formatPercentageTolerance(1), '1');
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
