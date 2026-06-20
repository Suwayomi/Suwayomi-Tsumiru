import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/constants/db_keys.dart';

void main() {
  test('appTheme default is Indigo Night (migration fallback)', () {
    expect(DBKeys.appTheme.initial, AppTheme.indigoNight);
  });

  test('customThemeColor default is the indigo accent', () {
    expect(DBKeys.customThemeColor.initial, 0xFF7C7BFF);
  });
}
