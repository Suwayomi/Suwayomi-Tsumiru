import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/misc/scalars.dart';

void main() {
  test('epoch seconds preserve a modern timestamp across a roundtrip', () {
    final timestamp = DateTime.utc(2026, 9, 7, 23, 17, 42);
    final encoded = dateTimeToJson(timestamp);
    expect(encoded, 1788823062);
    expect(dateTimeFromJson(encoded).toUtc(), timestamp);
  });
}
