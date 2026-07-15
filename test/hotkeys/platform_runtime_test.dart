import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

void main() {
  test('desktop implies keyboard runtime', () {
    expect(isKeyboardRuntime || !isDesktopPlatform, isTrue);
    expect(isDesktopPlatform, isTrue); // flutter_test host is desktop
  });
}
