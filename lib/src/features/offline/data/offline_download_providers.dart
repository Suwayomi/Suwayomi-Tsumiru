// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../auth/data/auth_credentials_store.dart';
import 'background/background_download_controller_shim.dart';
import 'chapter_download_engine.dart';
import '../../manga_book/data/downloads/downloads_repository.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../manga_book/domain/chapter_batch/chapter_batch_model.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'offline_background_downloads.dart';
import 'offline_database.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_manager.dart';
import 'offline_page_store.dart';
import 'offline_reconciler.dart';
import 'offline_repository.dart';
import 'offline_settings_providers.dart';
import 'reconcile_types.dart';

part 'offline_download_providers.g.dart';

/// True only on Android native, where the foreground-service worker owns
/// downloads (web-safe + correct in unit tests — see [isAndroidNative]).
bool get _useBgService => isAndroidNative;

/// THE single entry point that kicks off downloading after chapters have been
/// queued into drift. EVERY download trigger must call this — on Android it
/// starts the foreground-service worker, elsewhere it drains via the
/// main-isolate pump. Centralised (and overridable in tests) so no trigger can
/// ever again silently rely on the Android-disabled pump.
final downloadStarterProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    if (isAndroidNative) {
      await ref
          .read(backgroundDownloadControllerProvider)
          .ensureServiceRunning();
    } else {
      await ref.read(offlineDownloadCoordinatorProvider)?.pumpDownloads();
    }
  };
});

/// Live on-device download state for a chapter (none / queued / downloading /
/// downloaded / error). Always `none` when offline is unavailable.
@riverpod
Stream<OfflineDeviceState> offlineChapterState(Ref ref, int chapterId) {
  if (!ref.watch(offlineEnabledProvider)) {
    return Stream.value(OfflineDeviceState.none);
  }
  return ref.watch(offlineRepositoryProvider).watchChapterState(chapterId);
}

/// Live download progress for a chapter as a fraction 0..1 (pages on disk /
/// total pages), or null when the total isn't known yet — drives the
/// determinate progress arc on a downloading chapter, like Mihon/Komikku.
@riverpod
Stream<double?> offlineChapterProgress(Ref ref, int chapterId) {
  if (!ref.watch(offlineEnabledProvider)) {
    return Stream.value(null);
  }
  final repo = ref.watch(offlineRepositoryProvider);
  // Re-read the page total on every downloaded-page tick (instead of once up
  // front) so the arc flips from indeterminate to a real fraction the moment the
  // total becomes known — webtoon chapters only learn their page count when the
  // downloader resolves their pages mid-download.
  return repo.watchChapterDownloadedPages(chapterId).asyncMap((done) async {
    final total = (await repo.db.chapterById(chapterId))?.pageCount ?? 0;
    return total <= 0 ? null : (done / total).clamp(0.0, 1.0);
  }).distinct();
}

/// Save a chapter's pages to the device. Looks up the synced catalog row and
/// hands it to the download manager. No-op if offline is unavailable or the
/// chapter hasn't been synced (browse it online once first).
///
/// Manual save is sticky (pinned). If the chapter is not yet server-downloaded,
/// enqueues a server download first so Suwayomi fetches the source pages, then
/// pulls them immediately with `force: true` so the device copy is available as
/// soon as the server completes its own fetch.
Future<void> saveChapterToDevice(WidgetRef ref, int chapterId) async {
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (coordinator == null) return;
  final repo = ref.read(offlineRepositoryProvider);
  final chapter = await repo.chapterById(chapterId);
  if (chapter == null) return;
  // Manual save is sticky.
  await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, true);
  if (!chapter.serverIsDownloaded) {
    // Cascade: also commit a server download (grows the server library). The
    // device copy doesn't wait on it — the server streams pages from source.
    await ref
        .read(downloadsRepositoryProvider)
        .addChaptersBatchToDownloadQueue([chapterId]);
  }
  // Queue it (drift `queued` is the single source of truth). On Android the
  // foreground-service worker owns the downloading; elsewhere the main-isolate
  // pump drains it.
  await coordinator.queueChapter(chapterId);
  await ref.read(downloadStarterProvider)();
}

/// Record reading progress for a chapter. Persists it to the on-device catalog
/// FIRST (so it survives offline + app restart — the bug where progress was
/// lost reading offline), then pushes to the server; on a successful push the
/// dirty flag is cleared, otherwise it stays pending for the next online sync.
Future<void> recordReadingProgress(
  WidgetRef ref, {
  required int chapterId,
  required int lastPageRead,
  required bool isRead,
}) async {
  final offline = ref.read(offlineEnabledProvider);
  if (offline) {
    await ref.read(offlineDatabaseProvider).setChapterProgress(
          chapterId,
          lastPageRead: lastPageRead,
          isRead: isRead,
        );
  }
  final result = await AsyncValue.guard(
    () => ref.read(mangaBookRepositoryProvider).putChapter(
          chapterId: chapterId,
          patch: ChapterChange(lastPageRead: lastPageRead, isRead: isRead),
        ),
  );
  if (offline && !result.hasError) {
    await ref.read(offlineDatabaseProvider).clearProgressDirty(chapterId);
  }
}

/// Push any locally-recorded read progress that hasn't reached the server yet
/// (e.g. read while offline). Run at launch + after a manga's chapters sync, so
/// progress made offline syncs up once the connection returns.
Future<void> pushPendingProgress(ProviderContainer container) async {
  if (!container.read(offlineEnabledProvider)) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(mangaBookRepositoryProvider);
  for (final c in await db.dirtyProgressChapters()) {
    final result = await AsyncValue.guard(
      () => repo.putChapter(
        chapterId: c.id,
        patch: ChapterChange(lastPageRead: c.lastPageRead, isRead: c.isRead),
      ),
    );
    if (!result.hasError) await db.clearProgressDirty(c.id);
  }
}

/// Enforce device ⊆ server: when chapters are deleted on the server, drop any
/// device copies too. Silent; no-op when offline is unavailable.
Future<void> cascadeServerDeleteToDevice(
    WidgetRef ref, List<int> chapterIds) async {
  if (ref.read(offlineDownloadManagerProvider) == null) return;
  for (final id in chapterIds) {
    await deleteChapterFromDevice(ref, id);
  }
}

/// Remove a chapter's device copy.
Future<void> deleteChapterFromDevice(WidgetRef ref, int chapterId) async {
  final manager = ref.read(offlineDownloadManagerProvider);
  if (manager == null) return;
  // If the FGS worker is mid-download of this chapter, stop it first so it can't
  // resurrect files we're about to delete (the worker honours `remove` via the
  // engine's per-chapter cancel).
  if (_useBgService) {
    await ref.read(backgroundDownloadControllerProvider).onRemoved(chapterId);
  }
  final chapter = await ref.read(offlineRepositoryProvider).chapterById(chapterId);
  if (chapter != null) await manager.deleteChapter(chapter);
  await ref.read(offlineDatabaseProvider).setChapterPinned(chapterId, false);
}

/// The offline download orchestrator, wired with real network dependencies:
/// `fetchChapterPages` for the page URL list and an auth'd HTTP GET for each
/// page's bytes. Null on web / when offline storage is unavailable, so callers
/// can `ref.read(offlineDownloadManagerProvider)?.downloadChapter(c)`.
@riverpod
OfflineDownloadManager? offlineDownloadManager(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  final repo = ref.watch(mangaBookRepositoryProvider);
  return OfflineDownloadManager(
    db: ref.watch(offlineDatabaseProvider),
    store: ref.watch(offlinePageStoreProvider),
    fetchPageUrls: (chapterId) async =>
        (await repo.getChapterPages(chapterId: chapterId))?.pages ??
        const <String>[],
    fetchBytes: (url) => fetchOfflinePageBytes(ref, url),
  );
}

/// Fetch one page image's bytes with the active auth, resolved at CALL time
/// (never baked) — mirrors `ServerImage`'s request building: base API WITHOUT
/// the `/api` suffix (page URLs already carry `/api/...`), ui_login token as a
/// `?token=` query param, basic / simple_login via headers. Throws
/// [PageAuthException] on 401 so the download engine refreshes the token and
/// retries; any other non-200 is a plain (transient) exception.
Future<PageBytes> fetchOfflinePageBytes(Ref ref, String pageUrl) async {
  final authType = ref.read(authTypeKeyProvider);
  final basicToken = ref.read(credentialsProvider).valueOrNull;
  final creds = ref.read(authCredentialsStoreProvider).valueOrNull;
  final base = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: false,
  );
  var fetchUrl = '$base$pageUrl';

  final headers = <String, String>{};
  if (authType == AuthType.basic && basicToken != null) {
    headers['Authorization'] = basicToken;
  } else if (authType == AuthType.simpleLogin) {
    final cookie = creds?.simpleLoginCookieHeader;
    if (cookie != null) headers.addAll(cookie);
  } else if (authType == AuthType.uiLogin &&
      (creds?.uiAccessToken?.isNotEmpty ?? false)) {
    final sep = fetchUrl.contains('?') ? '&' : '?';
    fetchUrl =
        '$fetchUrl${sep}token=${Uri.encodeQueryComponent(creds!.uiAccessToken!)}';
  }

  final res = await http.get(Uri.parse(fetchUrl), headers: headers);
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw const PageAuthException();
  }
  if (res.statusCode != 200) {
    throw Exception('offline page fetch failed ($pageUrl): ${res.statusCode}');
  }
  return (bytes: res.bodyBytes, ext: pageImageExt(res.headers['content-type'], res.bodyBytes));
}

/// Manga ids that have at least one chapter downloaded on this device — used
/// by the "On device" library filter. Returns an empty set when offline is
/// unavailable so the filter is a no-op.
@riverpod
Future<Set<int>> offlineDeviceMangaIds(Ref ref) async {
  if (!ref.watch(offlineEnabledProvider)) return const {};
  return ref.watch(offlineRepositoryProvider).deviceDownloadedMangaIds();
}

/// The keep-offline rule currently set for a manga — used by the popup button
/// to show a checkmark on the active rule.
@riverpod
Future<OfflineKeepRule> mangaKeepRule(Ref ref, int mangaId) async {
  if (!ref.watch(offlineEnabledProvider)) return OfflineKeepRule.off;
  return ref.watch(offlineRepositoryProvider).keepRuleFor(mangaId);
}

/// How many of a manga's chapters are downloaded on this device — drives the
/// series Download/On-device button label.
@riverpod
Future<int> mangaDownloadedCount(Ref ref, int mangaId) async {
  if (!ref.watch(offlineEnabledProvider)) return 0;
  return (await ref.watch(offlineDatabaseProvider).downloadedChaptersForManga(mangaId))
      .length;
}

/// Live download progress for a series: how many chapters are downloaded vs
/// currently downloading/queued. Drives the live "Downloading N" button state.
@riverpod
Stream<({int downloaded, int inFlight})> mangaOfflineProgress(
    Ref ref, int mangaId) {
  if (!ref.watch(offlineEnabledProvider)) {
    return Stream.value((downloaded: 0, inFlight: 0));
  }
  return ref
      .watch(offlineDatabaseProvider)
      .watchChaptersForManga(mangaId)
      .map((rows) {
    var downloaded = 0;
    var inFlight = 0;
    for (final c in rows) {
      if (c.deviceState == OfflineDeviceState.downloaded) {
        downloaded++;
      } else if (c.deviceState == OfflineDeviceState.downloading ||
          c.deviceState == OfflineDeviceState.queued) {
        inFlight++;
      }
    }
    return (downloaded: downloaded, inFlight: inFlight);
  }).distinct(); // only rebuild the button when the counts actually change
}

/// Series with chapters on this device — downloaded AND actively downloading /
/// queued — with per-series counts + byte size. Drives the Downloads → Offline
/// files tab; live (re-emits as downloads progress or are removed).
@riverpod
Stream<List<({OfflineManga manga, int count, int inFlight, int bytes})>>
    offlineDownloadedSeries(Ref ref) async* {
  if (!ref.watch(offlineEnabledProvider)) {
    yield const [];
    return;
  }
  final db = ref.watch(offlineDatabaseProvider);
  final mangas = {for (final m in await db.libraryManga()) m.id: m};
  await for (final chapters in db.watchOfflineChapters()) {
    final done = <int, int>{};
    final inFlight = <int, int>{};
    final bytes = <int, int>{};
    for (final c in chapters) {
      if (c.deviceState == OfflineDeviceState.downloaded) {
        done[c.mangaId] = (done[c.mangaId] ?? 0) + 1;
        bytes[c.mangaId] = (bytes[c.mangaId] ?? 0) + c.bytes;
      } else {
        inFlight[c.mangaId] = (inFlight[c.mangaId] ?? 0) + 1;
      }
    }
    final ids = {...done.keys, ...inFlight.keys};
    final out = <({OfflineManga manga, int count, int inFlight, int bytes})>[];
    for (final id in ids) {
      final m = mangas[id];
      if (m != null) {
        out.add((
          manga: m,
          count: done[id] ?? 0,
          inFlight: inFlight[id] ?? 0,
          bytes: bytes[id] ?? 0,
        ));
      }
    }
    // Actively-downloading series first, then alphabetical.
    out.sort((a, b) {
      if ((a.inFlight > 0) != (b.inFlight > 0)) return a.inFlight > 0 ? -1 : 1;
      return a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase());
    });
    yield out;
  }
}

/// Total bytes of on-device offline content — for the storage settings UI.
@riverpod
Future<int> offlineUsageBytes(Ref ref) async {
  if (!ref.watch(offlineEnabledProvider)) return 0;
  return ref.read(offlineRepositoryProvider).totalDownloadedBytes();
}

/// Device-wide safety nets — read from persisted user settings.
@riverpod
SafetyNetConfig safetyNetConfig(Ref ref) => SafetyNetConfig(
      timeEvictEnabled:
          ref.watch(offlineTimeEvictEnabledProvider) ?? false,
      keepDays: ref.watch(offlineKeepDaysProvider) ?? 30,
      storageCapEnabled:
          ref.watch(offlineStorageCapEnabledProvider) ?? false,
      storageCapBytes:
          (ref.watch(offlineStorageCapMbProvider) ?? 2000) * 1024 * 1024,
    );

/// Concrete-deps core — no Ref/ProviderContainer in the signature, so the
/// controller, the launch path, and tests can all call it.
Future<void> reconcileMangaCore({
  required OfflineDatabase db,
  required OfflineRepository repo,
  required OfflineDownloadManager manager,
  required OfflineDownloadCoordinator coordinator,
  required SafetyNetConfig nets,
  required int mangaId,
}) {
  return OfflineReconciler(
    db: db,
    nets: nets,
    now: DateTime.now(),
    // Only QUEUE chapters here (mark them in the persistent backlog). Starting
    // the download is the caller's job (via downloadStarterProvider) — this core
    // must NOT start anything itself, so the Ref-less launch path and tests stay
    // in control. One failed queue-mark must NOT abort the rest.
    onDownload: (id) async {
      try {
        await coordinator.queueChapter(id);
      } catch (e) {
        logger.e('Offline: reconcile queue skipped for chapter $id: $e');
      }
    },
    onEvict: (id) async {
      try {
        final c = await repo.chapterById(id);
        if (c != null) await manager.deleteChapter(c);
      } catch (e) {
        logger.e('Offline: reconcile evict skipped for chapter $id: $e');
      }
    },
  ).reconcileManga(mangaId);
}

/// Controller / in-app entry point (generated Ref).
Future<void> reconcileManga(Ref ref, int mangaId) async {
  if (!ref.read(offlineEnabledProvider)) return;
  final manager = ref.read(offlineDownloadManagerProvider);
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  await reconcileMangaCore(
    db: ref.read(offlineDatabaseProvider),
    repo: ref.read(offlineRepositoryProvider),
    manager: manager,
    coordinator: coordinator,
    nets: ref.read(safetyNetConfigProvider),
    mangaId: mangaId,
  );
  // Keep-rule sync queued any missing chapters; now start downloading them.
  await ref.read(downloadStarterProvider)();
}

/// Widget entry point — same as [reconcileManga] but accepts a [WidgetRef].
Future<void> reconcileMangaWidget(WidgetRef ref, int mangaId) async {
  if (!ref.read(offlineEnabledProvider)) return;
  final manager = ref.read(offlineDownloadManagerProvider);
  final coordinator = ref.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  await reconcileMangaCore(
    db: ref.read(offlineDatabaseProvider),
    repo: ref.read(offlineRepositoryProvider),
    manager: manager,
    coordinator: coordinator,
    nets: ref.read(safetyNetConfigProvider),
    mangaId: mangaId,
  );
  // Start downloading the freshly-queued chapters. THIS was the missing wire
  // that made "Download all / unread" silently do nothing on Android.
  await ref.read(downloadStarterProvider)();
}

/// Launch entry point (main.dart holds a ProviderContainer, not a Ref).
Future<void> reconcileAllAtLaunch(ProviderContainer container) async {
  if (!container.read(offlineEnabledProvider)) return;
  final manager = container.read(offlineDownloadManagerProvider);
  final coordinator = container.read(offlineDownloadCoordinatorProvider);
  if (manager == null || coordinator == null) return;
  final db = container.read(offlineDatabaseProvider);
  final repo = container.read(offlineRepositoryProvider);
  final nets = container.read(safetyNetConfigProvider);
  for (final m in await db.libraryManga()) {
    await reconcileMangaCore(
        db: db, repo: repo, manager: manager, coordinator: coordinator,
        nets: nets, mangaId: m.id);
  }
}

/// Pick a file extension from the content-type, falling back to magic bytes.
/// Rendering sniffs the bytes regardless, so this only keeps filenames sensible.
String pageImageExt(String? contentType, List<int> bytes) {
  final ct = contentType?.toLowerCase() ?? '';
  if (ct.contains('png')) return 'png';
  if (ct.contains('webp')) return 'webp';
  if (ct.contains('gif')) return 'gif';
  if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';
  if (bytes.length >= 12) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[8] == 0x57) return 'webp';
  }
  return 'jpg';
}
