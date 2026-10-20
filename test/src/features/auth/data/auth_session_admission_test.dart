
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late ProviderContainer container;
  late AuthCredentialsStore store;

  Future<ProviderContainer> createContainer() async {
    final result = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(result.dispose);
    await result.read(authCredentialsStoreProvider.future);
    return result;
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A',
      'auth.ui.refreshToken': 'refresh-A',
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    preferences = await SharedPreferences.getInstance();
    container = await createContainer();
    store = container.read(authCredentialsStoreProvider.notifier);
    store.activateSession();
  });

  test(
    'committing B closes both old and newly captured work in activated A root',
    () async {
      final capturedA = store.captureSession();
      expect(capturedA(), isTrue);
      await store.saveUiLoginTokens(
        accessToken: 'B',
        refreshToken: 'refresh-B',
      );
      expect(store.sessionChanging, isFalse);
      expect(store.sessionAdmitted, isFalse);
      expect(capturedA(), isFalse);
      expect(store.captureSession()(), isFalse);

      final next = await createContainer();
      final nextStore = next.read(authCredentialsStoreProvider.notifier);
      nextStore.activateSession();
      expect(
        next.read(authCredentialsStoreProvider).requireValue.uiAccessToken,
        'B',
      );
      expect(nextStore.sessionAdmitted, isTrue);
      expect(nextStore.captureSession()(), isTrue);
      expect(store.captureSession()(), isFalse);
    },
  );
}
