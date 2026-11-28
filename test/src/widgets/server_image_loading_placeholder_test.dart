import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/texture_limit.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

class _Auth extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _UiLogin extends AuthTypeKey {
  @override
  AuthType? build() => AuthType.uiLogin;
}

class _Basic extends Credentials {
  @override
  Future<String?> build() async => null;
}

class _PendingCache extends Fake implements CacheManager {
  final stream = StreamController<FileResponse>.broadcast();

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) => Completer<File>().future;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => stream.stream;
}

const _cover = '/manga/1/thumbnail';
const _placeholderKey = ValueKey('caller-placeholder');

Widget _callerPlaceholder(
  BuildContext context,
  String url,
  DownloadProgress p,
) => const SizedBox(key: _placeholderKey, width: 40, height: 40);

Future<void> _pump(
  WidgetTester tester, {
  required Widget image,
  Future<int?>? textureLimit,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = _PendingCache();
  addTearDown(cache.stream.close);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authCredentialsStoreProvider.overrideWith(_Auth.new),
      authTypeKeyProvider.overrideWith(_UiLogin.new),
      credentialsProvider.overrideWith(_Basic.new),
      coverCacheManagerProvider.overrideWithValue(cache),
      if (textureLimit != null)
        textureLimitProvider.overrideWith((ref) => textureLimit),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authCredentialsStoreProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: image)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'texture-limit loading shows the caller placeholder, not the logo',
    (tester) async {
      await _pump(
        tester,
        image: ServerImage(
          imageUrl: _cover,
          progressIndicatorBuilder: _callerPlaceholder,
          imageBuilder: (context, provider) => const SizedBox(),
        ),
        textureLimit: Completer<int?>().future,
      );
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byType(CenterTsumiruShimmerIndicator), findsNothing);
    },
  );

  testWidgets(
    'crop-borders loading shows the caller placeholder, not the logo',
    (tester) async {
      await _pump(
        tester,
        image: const ServerImage(
          imageUrl: _cover,
          cropBorders: true,
          progressIndicatorBuilder: _callerPlaceholder,
        ),
      );
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byType(CenterTsumiruShimmerIndicator), findsNothing);
    },
  );

  testWidgets('crop-borders loading without a caller builder keeps the logo', (
    tester,
  ) async {
    await _pump(
      tester,
      image: const ServerImage(imageUrl: _cover, cropBorders: true),
    );
    expect(find.byType(CenterTsumiruShimmerIndicator), findsOneWidget);
    expect(find.byKey(_placeholderKey), findsNothing);
  });
}
