import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  test('safetyNetConfig reflects the persisted setting providers (defaults off)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    final cfg = c.read(safetyNetConfigProvider);
    expect(cfg.timeEvictEnabled, false);
    expect(cfg.keepDays, 30);
    expect(cfg.storageCapEnabled, false);
    expect(cfg.storageCapBytes, 2000 * 1024 * 1024);
  });
}
