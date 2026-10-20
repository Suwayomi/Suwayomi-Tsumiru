
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account changes replace HTTP and subscription clients', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    await container.read(customHttpHeadersProvider.future);
    final store = container.read(authCredentialsStoreProvider.notifier);
    final http = container.read(graphQlClientProvider);
    final socket = container.read(graphQlSubscriptionClientProvider);
    await store.withIdentityChange(() async {
      await store.saveUiLoginTokens(accessToken: 'A', refreshToken: 'R');
    });
    final nextHttp = container.read(graphQlClientProvider);
    final nextSocket = container.read(graphQlSubscriptionClientProvider);
    expect(nextHttp, isNot(same(http)));
    expect(nextSocket, isNot(same(socket)));
    await store.updateUiLoginAccessToken('A2');
    expect(container.read(graphQlClientProvider), same(nextHttp));
    expect(container.read(graphQlSubscriptionClientProvider), same(nextSocket));
  });
}
