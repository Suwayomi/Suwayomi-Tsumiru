import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_settings_format.dart';

void main() {
  test('formats bytes as human units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(2 * 1024 * 1024), '2.0 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });
}
