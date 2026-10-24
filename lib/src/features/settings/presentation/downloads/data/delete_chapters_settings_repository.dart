import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/webui_meta/webui_meta_repository.dart';
import '../../../../manga_book/domain/chapter/chapter_model.dart';
import './graphql/__generated__/global_meta.graphql.dart';

part 'delete_chapters_settings_repository.g.dart';

/// Shared WebUI global-meta keys; these have no per-device segment.
const kDeleteChaptersManuallyMarkedReadKey =
    'webUI_deleteChaptersManuallyMarkedRead';
const kDeleteChaptersWhileReadingKey = 'webUI_deleteChaptersWhileReading';
const kDeleteChaptersWithBookmarkKey = 'webUI_deleteChaptersWithBookmark';

class DeleteChaptersSettings {
  const DeleteChaptersSettings({
    this.deleteManuallyMarkedRead = false,
    this.deleteWhileReading = 0,
    this.deleteWithBookmark = false,
  });

  final bool deleteManuallyMarkedRead;

  /// 0 disables deletion; 1 deletes the last read chapter, 2 the second-to-last, up to 5.
  final int deleteWhileReading;

  final bool deleteWithBookmark;

  /// Missing global-meta keys use the disabled defaults.
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

  Future<void> setRawGlobalMeta(String key, String value) async {
    await ferryClient
        .mutate$SetGlobalMeta(
          Options$Mutation$SetGlobalMeta(
            variables: Variables$Mutation$SetGlobalMeta(key: key, value: value),
          ),
        )
        .getData((data) => data.setGlobalMeta);
  }

  /// Values must be JSON-encoded for WebUI compatibility.
  Future<void> setGlobalMeta(String key, String value) => WebUiMetaRepository(
    ferryClient,
  ).writeGlobalValue(key.substring('webUI_'.length), value);
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
    final previous = state;
    state = AsyncData(next);
    try {
      await ref
          .read(deleteChaptersSettingsRepositoryProvider)
          .setGlobalMeta(key, value);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  DeleteChaptersSettings get _current =>
      state.value ?? const DeleteChaptersSettings();

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

// Device copies use local preferences independently of server deletion settings.

/// 0 = off, 1 = delete the just-read chapter's device copy, 2..5 = the Nth back.
@riverpod
class LocalDeleteWhileReading extends _$LocalDeleteWhileReading
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.localDeleteWhileReading);
}

@riverpod
class LocalDeleteManuallyMarkedRead extends _$LocalDeleteManuallyMarkedRead
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.localDeleteManuallyMarkedRead);
}

@riverpod
class LocalDeleteWithBookmark extends _$LocalDeleteWithBookmark
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.localDeleteWithBookmark);
}

/// Downloads missing chapters in the slots-1 protection window behind the reader.
@riverpod
class LocalDownloadProtectionWindow extends _$LocalDownloadProtectionWindow
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.localDownloadProtectionWindow);
}

@riverpod
DeleteChaptersSettings localDeleteSettings(Ref ref) => DeleteChaptersSettings(
      deleteWhileReading: ref.watch(localDeleteWhileReadingProvider) ?? 0,
      deleteManuallyMarkedRead:
          ref.watch(localDeleteManuallyMarkedReadProvider) ?? false,
      deleteWithBookmark: ref.watch(localDeleteWithBookmarkProvider) ?? false,
    );

/// Returns the deletion target in reading order: 1 is [readChapterId], 2 its predecessor.
/// [chapters] is in display order; [isAscending] determines reading direction.
/// Returns null for nonpositive [slots] or an out-of-range target.
int? chapterIdToDeleteWhileReading(
  List<ChapterDto> chapters,
  bool isAscending,
  int readChapterId,
  int slots,
) {
  if (slots <= 0) return null;
  final current = chapters.indexWhere((c) => c.id == readChapterId);
  if (current < 0) return null;
  final step = isAscending ? -1 : 1;
  final target = current + step * (slots - 1);
  if (target < 0 || target >= chapters.length) return null;
  return chapters[target].id;
}
