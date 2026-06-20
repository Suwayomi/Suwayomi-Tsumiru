import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../constants/app_theme.dart';
import '../../../../../../constants/db_keys.dart';
import '../../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'app_theme_providers.g.dart';

@riverpod
class AppThemeKey extends _$AppThemeKey
    with SharedPreferenceEnumClientMixin<AppTheme> {
  @override
  AppTheme? build() =>
      initialize(DBKeys.appTheme, enumList: AppTheme.values);
}

@riverpod
class CustomThemeColor extends _$CustomThemeColor
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.customThemeColor);
}
