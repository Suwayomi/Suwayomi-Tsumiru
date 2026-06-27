import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import './graphql/__generated__/global_meta.graphql.dart';

part 'delete_chapters_settings_repository.g.dart';

/// The server stores Suwayomi-WebUI's client settings in its global-meta store.
/// These three keys drive the WebUI's "Delete chapters" download settings; we
/// read and write the SAME keys so the toggles stay in sync with the WebUI.
/// Global keys carry no per-device segment (unlike e.g. `webUI_4_pageScaleMode`).
const kDeleteChaptersManuallyMarkedReadKey =
    'webUI_deleteChaptersManuallyMarkedRead';
const kDeleteChaptersWhileReadingKey = 'webUI_deleteChaptersWhileReading';
const kDeleteChaptersWithBookmarkKey = 'webUI_deleteChaptersWithBookmark';

/// Suwayomi's "Delete chapters" settings, mirrored from the server's global
/// meta. Defaults match the WebUI's (all off / disabled).
class DeleteChaptersSettings {
  const DeleteChaptersSettings({
    this.deleteManuallyMarkedRead = false,
    this.deleteWhileReading = 0,
    this.deleteWithBookmark = false,
  });

  /// Delete a chapter's download when it is manually marked read.
  final bool deleteManuallyMarkedRead;

  /// Delete the Nth chapter behind the one being read (0 = disabled, 1 = the
  /// last read chapter, 2 = second-to-last, … up to 5). Matches the WebUI's
  /// numeric select.
  final int deleteWhileReading;

  /// Allow the two rules above to delete chapters that are bookmarked.
  final bool deleteWithBookmark;

  /// Parse the three settings out of the server's global-meta map (key → raw
  /// JSON-encoded value). Missing keys fall back to the WebUI defaults.
  factory DeleteChaptersSettings.fromMeta(Map<String, String> byKey) =>
      DeleteChaptersSettings(
        deleteManuallyMarkedRead:
            byKey[kDeleteChaptersManuallyMarkedReadKey] == 'true',
        deleteWhileReading:
            int.tryParse(byKey[kDeleteChaptersWhileReadingKey] ?? '') ?? 0,
        deleteWithBookmark: byKey[kDeleteChaptersWithBookmarkKey] == 'true',
      );

  DeleteChaptersSettings copyWith({
    bool? deleteManuallyMarkedRead,
    int? deleteWhileReading,
    bool? deleteWithBookmark,
  }) =>
      DeleteChaptersSettings(
        deleteManuallyMarkedRead:
            deleteManuallyMarkedRead ?? this.deleteManuallyMarkedRead,
        deleteWhileReading: deleteWhileReading ?? this.deleteWhileReading,
        deleteWithBookmark: deleteWithBookmark ?? this.deleteWithBookmark,
      );
}

class DeleteChaptersSettingsRepository {
  const DeleteChaptersSettingsRepository(this.ferryClient);

  final GraphQLClient ferryClient;

  Future<List<Fragment$GlobalMetaDto>?> getGlobalMetas() => ferryClient
      .query$GlobalMetas(Options$Query$GlobalMetas())
      .getData((data) => data.metas.nodes);

  /// Values are stored JSON-encoded (e.g. `"true"`, `"0"`), matching how the
  /// WebUI serializes them, so a write here is read back correctly by either
  /// client.
  Future<void> setGlobalMeta(String key, String value) => ferryClient
      .mutate$SetGlobalMeta(
        Options$Mutation$SetGlobalMeta(
          variables:
              Variables$Mutation$SetGlobalMeta(key: key, value: value),
        ),
      )
      .getData((data) => data.setGlobalMeta?.meta.key);
}

@riverpod
DeleteChaptersSettingsRepository deleteChaptersSettingsRepository(Ref ref) =>
    DeleteChaptersSettingsRepository(ref.watch(graphQlClientProvider));

@riverpod
class DeleteChaptersSettingsController
    extends _$DeleteChaptersSettingsController {
  @override
  Future<DeleteChaptersSettings> build() async {
    final metas = await ref
        .watch(deleteChaptersSettingsRepositoryProvider)
        .getGlobalMetas();
    final byKey = <String, String>{
      for (final m in metas ?? const <Fragment$GlobalMetaDto>[]) m.key: m.value,
    };
    return DeleteChaptersSettings.fromMeta(byKey);
  }

  Future<void> _write(String key, String value, DeleteChaptersSettings next) async {
    // Optimistic: reflect the toggle immediately, then persist to the server.
    final previous = state;
    state = AsyncData(next);
    try {
      await ref
          .read(deleteChaptersSettingsRepositoryProvider)
          .setGlobalMeta(key, value);
    } catch (_) {
      // The server didn't take it — revert so the UI doesn't lie about state.
      state = previous;
      rethrow;
    }
  }

  DeleteChaptersSettings get _current =>
      state.valueOrNull ?? const DeleteChaptersSettings();

  Future<void> setDeleteManuallyMarkedRead(bool value) => _write(
        kDeleteChaptersManuallyMarkedReadKey,
        value ? 'true' : 'false',
        _current.copyWith(deleteManuallyMarkedRead: value),
      );

  Future<void> setDeleteWhileReading(int value) => _write(
        kDeleteChaptersWhileReadingKey,
        '$value',
        _current.copyWith(deleteWhileReading: value),
      );

  Future<void> setDeleteWithBookmark(bool value) => _write(
        kDeleteChaptersWithBookmarkKey,
        value ? 'true' : 'false',
        _current.copyWith(deleteWithBookmark: value),
      );
}
