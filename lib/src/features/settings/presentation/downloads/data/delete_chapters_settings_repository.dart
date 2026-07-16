import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../manga_book/domain/chapter/chapter_model.dart';
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

// --- ON-DEVICE delete settings (independent of the server settings above) ----
// A SEPARATE set of toggles that govern deleting THIS phone's downloaded copies
// as you read. Stored in local shared prefs (offline-safe, Tsumiru-only) — never
// coupled to the server's global-meta settings. All default off, same shape as
// the server settings so the two UI sections are identical.

/// 0 = off, 1 = delete the just-read chapter's device copy, 2..5 = the Nth back.
@riverpod
class LocalDeleteWhileReading extends _$LocalDeleteWhileReading
    with SharedPreferenceClientMixin<int> {
  @override
  int? build() => initialize(DBKeys.localDeleteWhileReading);
}

/// Delete a chapter's device copy when it is manually marked read.
@riverpod
class LocalDeleteManuallyMarkedRead extends _$LocalDeleteManuallyMarkedRead
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.localDeleteManuallyMarkedRead);
}

/// Allow the two on-device rules to delete bookmarked chapters too.
@riverpod
class LocalDeleteWithBookmark extends _$LocalDeleteWithBookmark
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.localDeleteWithBookmark);
}

/// The on-device delete settings as one value (defaults all off).
@riverpod
DeleteChaptersSettings localDeleteSettings(Ref ref) => DeleteChaptersSettings(
      deleteWhileReading: ref.watch(localDeleteWhileReadingProvider) ?? 0,
      deleteManuallyMarkedRead:
          ref.watch(localDeleteManuallyMarkedReadProvider) ?? false,
      deleteWithBookmark: ref.watch(localDeleteWithBookmarkProvider) ?? false,
    );

/// The id of the chapter to delete when [readChapterId] is read with
/// "after reading automatically delete" = [slots] (1 = the just-read chapter,
/// 2 = the one before it, …). Null when [slots] <= 0 or the target falls outside
/// the list. [chapters] is the manga's chapter list in display order and
/// [isAscending] is the sort direction — together they define reading order,
/// exactly as the reader's own next/previous navigation does, so we only ever
/// target a chapter already behind the reader (never the one ahead). Shared by
/// the on-device and server delete paths.
int? chapterIdToDeleteWhileReading(
  List<ChapterDto> chapters,
  bool isAscending,
  int readChapterId,
  int slots,
) {
  if (slots <= 0) return null;
  final current = chapters.indexWhere((c) => c.id == readChapterId);
  if (current < 0) return null;
  // The reading-backward step in list-index terms — mirrors how
  // getNextAndPreviousChapters derives the "previous" chapter from the sort.
  final step = isAscending ? -1 : 1;
  final target = current + step * (slots - 1);
  if (target < 0 || target >= chapters.length) return null;
  return chapters[target].id;
}
