import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/settings_repository.dart';
import '../domain/settings/settings.dart';

part 'server_controller.g.dart';

@riverpod
class Settings extends _$Settings {
  @override
  Future<SettingsDto?> build() =>
      ref.watch(settingsRepositoryProvider).getServerSettings();

  // Set directly: copyWithData only touches the data branch, so an update
  // landing while loading/errored was silently dropped.
  void updateState(SettingsDto value) => state = AsyncValue.data(value);
}
