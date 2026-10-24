import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../global_providers/global_providers.dart';
import '../extensions/custom_extensions.dart';
import '__generated__/webui_meta.graphql.dart';
import 'webui_meta_codec.dart';
import 'webui_meta_repository.dart';

final webUiSettingsProvider =
    AsyncNotifierProvider<WebUiSettings, Map<String, String>>(
      WebUiSettings.new,
      retry: (_, _) => null,
    );

class WebUiSettings extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final result = await ref
        .watch(graphQlClientProvider)
        .query$GetWebUiGlobalMetas(
          Options$Query$GetWebUiGlobalMetas(fetchPolicy: FetchPolicy.noCache),
        )
        .getData(
          (data) => {for (final meta in data.metas.nodes) meta.key: meta.value},
        );
    return result ?? {};
  }

  Future<void> write(String key, String value) async {
    final metas = await future;
    await WebUiMetaRepository(
      ref.read(graphQlClientProvider),
    ).writeGlobalValue(key, value, metas);
    if (!ref.mounted) return;
    state = AsyncData({
      ...state.requireValue,
      ...planWebUiWrite(metas, key, value).set,
    });
  }
}

final webUiBoolProvider = Provider.family<bool, String>((ref, key) {
  final value = readWebUiValue(
    ref.watch(webUiSettingsProvider).value ?? {},
    key,
  );
  return value == null ? key == 'fuzzySearch' : decodeWebUiBool(value);
});

final downloadAheadLimitProvider = Provider<int>((ref) {
  final value = readWebUiValue(
    ref.watch(webUiSettingsProvider).value ?? {},
    'downloadAheadLimit',
  );
  final limit = value == null ? 0 : decodeWebUiInt(value, defaultValue: 0);
  return limit == 0 ? 0 : limit.clamp(2, 10);
});
