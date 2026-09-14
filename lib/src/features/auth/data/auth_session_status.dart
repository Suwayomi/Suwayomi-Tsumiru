import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'auth_credentials_store.dart';

final hasStoredCredentialsProvider = Provider<bool>((ref) {
  final credentials = ref.watch(authCredentialsStoreProvider).value;
  return switch (ref.watch(authTypeKeyProvider)) {
    AuthType.uiLogin =>
      credentials?.uiAccessToken?.isNotEmpty == true &&
          credentials?.uiRefreshToken?.isNotEmpty == true,
    AuthType.simpleLogin => credentials?.simpleLoginCookie?.isNotEmpty == true,
    AuthType.basic => ref.watch(credentialsProvider).value?.isNotEmpty == true,
    _ => false,
  };
});
