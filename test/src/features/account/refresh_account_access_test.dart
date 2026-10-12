import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late int checks;
  late AccountCapability answer;
  var now = DateTime(2026, 9, 26, 18);

  setUp(() async {
    checks = 0;
    answer = AccountCapability.supported;
    now = DateTime(2026, 9, 26, 18);
    accountAccessClock = () => now;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        accountAccessProvider.overrideWith((ref) async {
          checks++;
          return AccountAccess(capability: answer);
        }),
      ],
    );
    await container.read(authCredentialsStoreProvider.future);
  });

  tearDown(() {
    container.dispose();
    accountAccessClock = DateTime.now;
  });

  Future<AccountAccess> refresh() =>
      container.read(refreshAccountAccessProvider)();

  test('back-to-back verifications share one account check', () async {
    // The launch reconcile verifies the grant once per series.
    for (var i = 0; i < 50; i++) {
      expect((await refresh()).capability, AccountCapability.supported);
    }
    expect(checks, 1);
  });

  test('a verification after the reuse window checks again', () async {
    await refresh();
    now = now.add(accountAccessReuse);
    await refresh();
    expect(checks, 2);
  });

  test('an unknown answer is never reused', () async {
    answer = AccountCapability.unknown;
    await refresh();
    answer = AccountCapability.supported;
    expect((await refresh()).capability, AccountCapability.supported);
    expect(checks, 2);
  });
}
