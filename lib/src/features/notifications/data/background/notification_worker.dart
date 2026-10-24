// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../../constants/endpoints.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../utils/crash/crash_log.dart';
import '../../../../utils/crash/diagnostics.dart';
import '../../../../utils/network/gateway_status.dart';
import '../../../auth/data/secure_credentials_provider.dart';
import '../../../offline/data/background/background_chapter_fetch.dart';
import '../../../offline/data/background/background_download_lock.dart';
import '../../../offline/data/background/background_schedule.dart';
import '../../../offline/data/background/background_token_record.dart';
import '../../../offline/data/background/catchup_download_executor.dart';
import '../../../offline/data/background/catchup_work_spec.dart';
import '../../../offline/data/background/record_seal.dart';
import '../../domain/new_chapter_detection.dart';
import '../local_notification_service.dart';
import '../notification_state_store.dart';
import 'notification_background_client.dart';

/// Returns false only for transient failures; persists the outbox before publishing and advancing the cursor.
Future<bool> runNewChapterCheck() async {
  // Each WorkManager isolate needs its own diagnostic sink.
  final crashLogPath = await initCrashLog();
  setDiagnosticSink((line) => writeCrashLog(crashLogPath, line));
  // Load the seal key before reading encrypted token records.
  await RecordSeal.load(kSecureStorage);

  final store = await NotificationStateStore.open();
  final config = store.readConfig();
  final token = store.readTokenRecord();
  if (config == null || token == null || !config.matchesToken(token)) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-worker: '
      'check-skipped reason=no-config\n',
    );
    return true;
  }

  final catchupStore = await CatchupStateStore.open();
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-worker: check-started '
    'newChapters=${config.newChaptersEnabled} catchup=${catchupStore.enabled} '
    'appUpdates=${config.appUpdatesEnabled} '
    'extUpdates=${config.extensionUpdatesEnabled}\n',
  );

  final l10n = lookupAppLocalizations(_deviceLocale());
  final notifier = LocalNotificationService();
  await notifier.init(onBackgroundTap: notificationActionCallback);
  // Resolve reachability for this network; identity remains tied to the foreground-verified address.
  final endpoint = await config.endpoint.forThisNetwork(source: 'worker');
  final client = NotificationBackgroundClient(
    endpoint: endpoint,
    record: token,
    broker: _brokerFor(endpoint, token),
    isCancelled: () =>
        config.catalogServerId != null && !catchupStore.matchesIdentity(config),
    admitDownload: () async {
      await catchupStore.reload();
      return catchupStore.matchesIdentity(config) &&
          !catchupStore.paused &&
          !catchupStore.downloadPermissionPaused(config.catalogServerId!);
    },
    onDownloadPermissionDenied: () async {
      final catalogId = config.catalogServerId;
      if (catalogId == null) return;
      await catchupStore.recordDownloadPermission(
        catalogId,
        allowed: false,
        expectedRevision: catchupStore.downloadPermissionRevision(catalogId),
        isCurrent: () => catchupStore.matchesIdentity(config),
      );
    },
  );

  final network = await Connectivity().checkConnectivity();
  final unmetered =
      network.contains(ConnectivityResult.wifi) ||
      network.contains(ConnectivityResult.ethernet);
  var notificationPolicy = !config.wifiOnly || unmetered;
  if (notificationPolicy && config.chargingOnly) {
    try {
      final battery = await Battery().batteryState;
      notificationPolicy =
          battery == BatteryState.charging || battery == BatteryState.full;
    } catch (_) {
      notificationPolicy = false;
    }
  }
  var ok = true;
  if (notificationPolicy && config.newChaptersEnabled) {
    ok = await runNewChapters(store, config, client, notifier, l10n);
  }
  if (catchupStore.enabled &&
      !catchupStore.paused &&
      config.catalogServerId != null &&
      !catchupStore.downloadPermissionPaused(config.catalogServerId!) &&
      catchupStore.matchesIdentity(config) &&
      (!(catchupStore.readSpec()?.wifiOnly ?? true) || unmetered)) {
    ok = await _runDownloadResolution(catchupStore, config, client) && ok;
  }
  if (!catchupStore.paused &&
      config.catalogServerId != null &&
      !catchupStore.downloadPermissionPaused(config.catalogServerId!) &&
      ((catchupStore.enabled && catchupStore.downloadEnabled) ||
          (catchupStore.readSpec()?.queuedChapters.isNotEmpty ?? false))) {
    ok =
        await runCatchupDownloads(
          catchupStore: catchupStore,
          config: config,
          endpoint: endpoint,
          record: client.currentRecord,
          broker: client.broker,
        ) &&
        ok;
  }
  if (notificationPolicy && config.appUpdatesEnabled) {
    await _checkAppUpdate(store, config, client, notifier, l10n);
  }
  if (notificationPolicy && config.extensionUpdatesEnabled) {
    await _checkExtensionUpdates(store, config, client, notifier, l10n);
  }
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-worker: '
    'check-finished ok=$ok\n',
  );
  return ok;
}

Future<void> _checkAppUpdate(
  NotificationStateStore store,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
  LocalNotificationService notifier,
  AppLocalizations l10n,
) async {
  final release = await client.fetchLatestRelease();
  if (release == null) return;
  if (release.version == config.appVersion) return; // up to date
  await _withNotificationOwner(config, (current) async {
    if (release.version == current.lastNotifiedAppVersion) return;
    await current.setLastNotifiedAppVersion(release.version);
    await notifier.showAppUpdate(
      l10n.notificationAppUpdateTitle,
      l10n.notificationAppUpdateBody(release.version),
      release.url.isEmpty ? null : release.url,
    );
  });
}

Future<void> _checkExtensionUpdates(
  NotificationStateStore store,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
  LocalNotificationService notifier,
  AppLocalizations l10n,
) async {
  final count = await client.countExtensionUpdates();
  await _withNotificationOwner(config, (current) async {
    final previous = current.lastExtensionUpdateCount;
    await current.setLastExtensionUpdateCount(count);
    if (count <= previous) return;
    await notifier.showExtensionUpdates(
      l10n.notificationExtensionUpdateTitle,
      l10n.notificationExtensionUpdateBody(count),
    );
  });
}

Future<bool> _withNotificationOwner(
  NotificationWorkerConfig expected,
  Future<void> Function(NotificationStateStore) action,
) => withBackgroundScheduleLock(() async {
  final current = await NotificationStateStore.open();
  final config = current.readConfig();
  final token = current.readTokenRecord();
  final controls = await CatchupStateStore.open();
  if (config == null ||
      token == null ||
      !config.matchesToken(token) ||
      !expected.matchesToken(token) ||
      !controls.identityAuthorized ||
      controls.identityEpoch != expected.identityEpoch ||
      jsonEncode(config.toJson()) != jsonEncode(expected.toJson())) {
    return false;
  }
  await action(current);
  return true;
});

Future<bool> runNewChapters(
  NotificationStateStore store,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
  LocalNotificationService notifier,
  AppLocalizations l10n,
) async {
  // Replay the durable outbox before scanning; stable IDs replace already-posted notifications.
  final stranded = store.readOutbox();
  if (stranded != null && stranded.matchesConfig(config)) {
    if (!await _publish(
      notifier,
      client,
      l10n,
      config,
      stranded.pending,
      stranded.nextWatermark,
    )) {
      return true;
    }
  }

  var watermark = store.readWatermark(config.sessionFingerprint!);

  // Seed on first enable so existing chapters are not announced as new.
  if (watermark.fetchedAt == 0 && watermark.recent.isEmpty) {
    final seed = await _seedWatermark(client);
    if (seed == null) return false; // transient — retry next wake
    await _withNotificationOwner(
      config,
      (current) => current.writeWatermark(config.sessionFingerprint!, seed),
    );
    return true;
  }

  final gte = _overlapStart(watermark);
  final all = <NotifChapter>[];
  final mangaCategories = <int, Set<int>>{};
  String? after;
  while (true) {
    final page = await client.fetchNewChaptersPage(
      fetchedAtGte: '$gte',
      after: after,
    );
    if (page == null) return false; // transient — retry next wake
    all.addAll(page.nodes);
    for (final n in page.nodes) {
      mangaCategories[n.mangaId] = n.categoryIds;
    }
    if (!page.hasNextPage || page.endCursor == null) break;
    after = page.endCursor;
  }

  final allowedMangaIds = config.allowedMangaIds(mangaCategories);
  final result = detectNewChapters(
    candidates: [
      for (final n in all)
        (
          id: n.id,
          mangaId: n.mangaId,
          chapterNumber: n.chapterNumber,
          fetchedAt: n.fetchedAt,
        ),
    ],
    watermark: watermark,
    allowedMangaIds: allowedMangaIds,
  );

  final notifyList = [
    for (final g in result.groups)
      '${g.mangaId}:${g.chapters.map((c) => c.id).join('|')}',
  ].join(',');
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-notify: detected '
    'candidates=${all.length} groups=${result.groups.length} '
    'notify=[$notifyList]\n',
  );

  final notifiedIds = {
    for (final g in result.groups) for (final c in g.chapters) c.id,
  };
  final alreadyNotified = <int>[];
  final outOfCategoryScope = <int>[];
  final zeroFetchedAt = <int>[];
  for (final n in all) {
    if (n.fetchedAt == 0) zeroFetchedAt.add(n.id);
    if (notifiedIds.contains(n.id)) continue;
    if (watermark.recent.containsKey(n.id)) {
      alreadyNotified.add(n.id);
    } else if (allowedMangaIds != null && !allowedMangaIds.contains(n.mangaId)) {
      outOfCategoryScope.add(n.id);
    }
  }
  if (alreadyNotified.isNotEmpty ||
      outOfCategoryScope.isNotEmpty ||
      zeroFetchedAt.isNotEmpty) {
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-notify: excluded '
      'alreadyNotified=[${alreadyNotified.join(',')}] '
      'outOfCategoryScope=[${outOfCategoryScope.join(',')}] '
      'zeroFetchedAt=[${zeroFetchedAt.join(',')}]\n',
    );
  }

  if (result.groups.isEmpty) {
    await _withNotificationOwner(
      config,
      (current) =>
          current.writeWatermark(config.sessionFingerprint!, result.watermark),
    );
    return true;
  }

  final byId = {for (final n in all) n.id: n};
  final pending = [for (final g in result.groups) _toPending(g, byId)];
  await _publish(notifier, client, l10n, config, pending, result.watermark);
  return true;
}

// fetchedAt and the overlap window both use epoch seconds.
int _overlapStart(NewChapterWatermark cursor) =>
    (cursor.fetchedAt - kDefaultOverlapSeconds).clamp(0, cursor.fetchedAt);

// Seed overlap entries as seen to avoid notifying the existing backlog; null means fetch failure.
Future<NewChapterWatermark?> _seedWatermark(
  NotificationBackgroundClient client,
) async {
  final maxFetched = await client.serverMaxFetchedAt();
  if (maxFetched == 0) return const NewChapterWatermark();
  final window = <NotifChapter>[];
  String? after;
  while (true) {
    final page = await client.fetchNewChaptersPage(
      fetchedAtGte: '${_overlapStart(NewChapterWatermark(fetchedAt: maxFetched))}',
      after: after,
    );
    if (page == null) return null;
    window.addAll(page.nodes);
    if (!page.hasNextPage || page.endCursor == null) break;
    after = page.endCursor;
  }
  final seed = seedNewChapterWatermark(
    maxFetched: maxFetched,
    window: [
      for (final n in window)
        (
          id: n.id,
          mangaId: n.mangaId,
          chapterNumber: n.chapterNumber,
          fetchedAt: n.fetchedAt,
        ),
    ],
  );
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] new-chapter-cursor: seeded '
    'fetchedAt=$maxFetched recent=${seed.recent.length}\n',
  );
  return seed;
}

// Downloads have a separate cursor and keep-rule scope; muting notifications must not stop downloads.
Future<bool> _runDownloadResolution(
  CatchupStateStore catchupStore,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
) async {
  final support = await getApplicationSupportDirectory();
  final initialSpec = catchupStore.readSpec();
  if (initialSpec == null) return true;
  final storagePath = initialSpec.storagePath('${support.path}/offline');
  final lock = BackgroundDownloadLock(File('$storagePath/.bg_lock'));
  if (!await lock.acquire('resolve')) return true;
  try {
    await catchupStore.reload();
    if (catchupStore.paused ||
        !catchupStore.matchesIdentity(config) ||
        catchupStore.downloadPermissionPaused(config.catalogServerId!)) {
      return true;
    }
    if (!await client.verifyDownloadAccess()) return true;
    final spec = catchupStore.readSpec();
    if (spec == null ||
        spec.manga.isEmpty ||
        spec.storagePath('${support.path}/offline') != storagePath) {
      return true;
    }
    // A server switch invalidates the spec until the foreground rewrites it.
    if (spec.serverId != catchupStore.catalogServerId) return true;

    if (!await verifyBackgroundServerIdentity(
      target: BackgroundServerTarget(
        serverBase: client.endpoint.baseUrl,
        port: client.endpoint.port,
        addPort: client.endpoint.addPort,
      ),
      record: client.currentRecord,
      broker: client.broker,
      expected: spec.serverId,
    ).timeout(const Duration(seconds: 10), onTimeout: () => false)) {
      return true;
    }

    var ledger = catchupStore.readLedger(spec.serverId);

    // First enable does not backfill; foreground launch handles the backlog.
    if (ledger.cursor.fetchedAt == 0 && ledger.cursor.recent.isEmpty) {
      final seed = await _seedWatermark(client);
      if (seed == null) return false; // transient — retry next wake
      if (await lock.yieldRequested()) return true;
      await catchupStore.writeLedger(
        spec.serverId,
        ledger.copyWith(cursor: seed),
      );
      return true;
    }

    final gte = _overlapStart(ledger.cursor);
    final all = <NotifChapter>[];
    String? after;
    while (true) {
      if (await lock.yieldRequested()) return true;
      final page = await client.fetchNewChaptersPage(
        fetchedAtGte: '$gte',
        after: after,
      );
      if (page == null) return false; // transient — retry next wake
      all.addAll(page.nodes);
      if (!page.hasNextPage || page.endCursor == null) break;
      after = page.endCursor;
    }

    final result = detectNewChapters(
      candidates: [
        for (final n in all)
          (
            id: n.id,
            mangaId: n.mangaId,
            chapterNumber: n.chapterNumber,
            fetchedAt: n.fetchedAt,
          ),
      ],
      watermark: ledger.cursor,
      allowedMangaIds: spec.keepRuleMangaIds,
    );

    final droppedOutOfScope = <int, int>{
      for (final n in all)
        if (!ledger.cursor.recent.containsKey(n.id) &&
            !spec.keepRuleMangaIds.contains(n.mangaId))
          n.id: n.mangaId,
    };
    final queuedList = [
      for (final group in result.groups)
        '${group.mangaId}:${group.chapters.map((c) => c.id).join('|')}',
    ].join(',');
    final droppedList = droppedOutOfScope.entries
        .map((e) => '${e.value}:${e.key}')
        .join(',');
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-download-resolve: '
      'candidates=${all.length} queued=[$queuedList] '
      'droppedOutOfScope=[$droppedList]\n',
    );

    // Persist obligations and cursor atomically so every detected chapter remains owed.
    final pendingDownloads = {...ledger.pendingDownloads};
    for (final group in result.groups) {
      for (final c in group.chapters) {
        pendingDownloads[c.id] = group.mangaId;
      }
    }
    if (await lock.yieldRequested()) return true;
    await catchupStore.writeLedger(
      spec.serverId,
      ledger.copyWith(
        cursor: result.watermark,
        pendingDownloads: pendingDownloads,
      ),
    );
    return true;
  } finally {
    await lock.release();
  }
}

PendingSeriesNotification _toPending(
  MangaNewChapters group,
  Map<int, NotifChapter> byId,
) {
  final first = byId[group.chapters.first.id]!;
  return PendingSeriesNotification(
    mangaId: group.mangaId,
    mangaTitle: first.mangaTitle,
    thumbnailUrl: first.thumbnailUrl,
    chapterIds: [for (final c in group.chapters) c.id],
    chapterNumbers: [for (final c in group.chapters) c.chapterNumber],
    firstChapterId: group.chapters.first.id,
    totalCount: group.chapters.length,
  );
}

Future<bool> _publish(
  LocalNotificationService notifier,
  NotificationBackgroundClient client,
  AppLocalizations l10n,
  NotificationWorkerConfig config,
  List<PendingSeriesNotification> pending,
  NewChapterWatermark watermark,
) async {
  final summaryTitle = l10n.notificationNewChaptersTitle;
  final summaryText = pending.length == 1 && !config.hideContent
      ? pending.first.mangaTitle
      : l10n.notificationNewChaptersSummary(pending.length);
  final series = <SeriesNotificationContent>[];
  for (final p in pending) {
    series.add(
      SeriesNotificationContent(
        mangaId: p.mangaId,
        title: p.mangaTitle,
        body: _describe(l10n, p),
        firstChapterId: p.firstChapterId,
        chapterIds: p.chapterIds,
        coverPath: config.hideContent
            ? null
            : await _fetchCover(client, p, config.sessionFingerprint!),
      ),
    );
  }
  return _withNotificationOwner(config, (current) async {
    await current.writeOutbox(
      NotificationOutbox(
        pending: pending,
        nextWatermark: watermark,
        sessionFingerprint: config.sessionFingerprint,
      ),
    );
    await notifier.showNewChapters(
      summaryTitle: summaryTitle,
      summaryText: summaryText,
      summaryLines: [for (final p in pending) p.mangaTitle],
      hideContent: config.hideContent,
      markReadLabel: l10n.notificationActionMarkRead,
      viewLabel: l10n.notificationActionView,
      downloadLabel: l10n.notificationActionDownload,
      series: series,
      identityEpoch: config.identityEpoch,
      catalogServerId: config.catalogServerId,
      sessionFingerprint: config.sessionFingerprint,
    );
    await current.writeWatermark(config.sessionFingerprint!, watermark);
    await current.clearOutbox();
  });
}

// Headless actions require a top-level vm:entry-point callback.
@pragma('vm:entry-point')
void notificationActionCallback(NotificationResponse response) {
  handleNotificationAction(response.actionId, response.payload);
}

/// Handles Mark-read and Download without UI; View is routed by the foreground.
Future<void> handleNotificationAction(String? actionId, String? payload) async {
  if (actionId != kNotifActionMarkRead && actionId != kNotifActionDownload) {
    return;
  }
  final p = NotificationPayload.decode(payload);
  if (p.chapterIds.isEmpty) return;
  // A headless isolate must load its own seal key.
  if (!RecordSeal.ready) await RecordSeal.load(kSecureStorage);
  final store = await NotificationStateStore.open();
  final config = store.readConfig();
  final token = store.readTokenRecord();
  if (config == null ||
      token == null ||
      !config.matchesToken(token) ||
      !p.matchesConfig(config)) {
    return;
  }
  final catchupStore = await CatchupStateStore.open();
  if (actionId == kNotifActionDownload &&
      !catchupStore.matchesIdentity(config)) {
    return;
  }
  if (actionId == kNotifActionDownload &&
      config.catalogServerId != null &&
      catchupStore.downloadPermissionPaused(config.catalogServerId!)) {
    return;
  }
  final endpoint = await config.endpoint.forThisNetwork(
    source: 'notification-action',
  );
  final client = NotificationBackgroundClient(
    endpoint: endpoint,
    record: token,
    broker: _brokerFor(endpoint, token),
    isCancelled: () =>
        actionId == kNotifActionDownload &&
        !catchupStore.matchesIdentity(config),
    admitDownload: () async {
      await catchupStore.reload();
      return catchupStore.matchesIdentity(config) &&
          !catchupStore.paused &&
          !catchupStore.downloadPermissionPaused(config.catalogServerId!);
    },
    onDownloadPermissionDenied: () async {
      final catalogId = config.catalogServerId;
      if (catalogId == null) return;
      await catchupStore.recordDownloadPermission(
        catalogId,
        allowed: false,
        expectedRevision: catchupStore.downloadPermissionRevision(catalogId),
        isCurrent: () => catchupStore.matchesIdentity(config),
      );
    },
  );
  if (actionId == kNotifActionMarkRead) {
    await client.markRead(p.chapterIds);
  } else {
    await client.enqueueDownloads(p.chapterIds);
  }
}

// Missing covers return null and fall back to text notifications.
Future<String?> _fetchCover(
  NotificationBackgroundClient client,
  PendingSeriesNotification p,
  String sessionFingerprint,
) async {
  final url = p.thumbnailUrl;
  if (url == null || url.isEmpty) return null;
  try {
    final bytes = await client.fetchCover(url);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/notif_cover_${sessionFingerprint}_${p.mangaId}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

String _describe(AppLocalizations l10n, PendingSeriesNotification p) {
  final label = newChaptersLabel(p.chapterNumbers, p.totalCount);
  return switch (label) {
    GenericNewChapters(:final count) => l10n.notificationChaptersGeneric(count),
    SingleNewChapter(:final number, :final more) =>
      more == 0
          ? l10n.notificationChapterSingle(number)
          : l10n.notificationChapterSingleAndMore(number, more),
    MultipleNewChapters(:final numbers, :final more) =>
      more == 0
          ? l10n.notificationChaptersMultiple(numbers.join(', '))
          : l10n.notificationChaptersMultipleAndMore(numbers.join(', '), more),
  };
}

TokenBroker _brokerFor(
  NotificationEndpoint ep,
  BackgroundTokenRecord original,
) {
  final epoch = original.identityEpoch;
  return TokenBroker(
    expectedIdentity: original,
    read: () async =>
        (await NotificationStateStore.open()).readTokenRecord() ??
        const BackgroundTokenRecord(gen: 0, authType: 'none'),
    write: (r) => withBackgroundScheduleLock(() async {
      final currentStore = await NotificationStateStore.open();
      final current = currentStore.readTokenRecord();
      final controls = await CatchupStateStore.open();
      if (controls.identityAuthorized &&
          currentStore.readConfig()?.matchesToken(r) == true &&
          controls.identityEpoch == epoch &&
          current != null &&
          current.sameIdentity(r) &&
          r.gen > current.gen) {
        await currentStore.writeTokenRecord(r);
      }
    }),
    refreshFn: (refreshToken) async {
      final endpoint = Endpoints.baseApi(
        baseUrl: ep.baseUrl,
        port: ep.port,
        addPort: ep.addPort,
        isGraphQl: true,
      );
      // Read auth and its headers together after any rotation.
      Map<String, String> extraHeaders = const {};
      try {
        extraHeaders = original.extraHeaders;
      } catch (_) {}
      try {
        final res = await http
            .post(
              Uri.parse(endpoint),
              headers: applyIsolateCustomHeaders({
                'Content-Type': 'application/json',
              }, extraHeaders),
              body: jsonEncode({
                'query':
                    r'mutation RefreshToken($input: RefreshTokenInput!){ refreshToken(input: $input){ accessToken } }',
                'variables': {
                  'input': {'refreshToken': refreshToken},
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        // A gateway error proves reachability failure, not refresh-token rejection.
        if (isGatewayStatus(res.statusCode)) {
          logBackgroundRefresh(
            'notify',
            'gateway status=${res.statusCode} transient=true',
          );
          return (tokens: null, transient: true);
        }
        if (res.statusCode != 200) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-refresh: '
            'rejected status=${res.statusCode}\n',
          );
          return (tokens: null, transient: false);
        }
        final decoded = jsonDecode(res.body) as Map<String, Object?>;
        final data = decoded['data'] as Map<String, Object?>?;
        final access =
            (data?['refreshToken'] as Map<String, Object?>?)?['accessToken']
                as String?;
        if (access == null || access.isEmpty) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-refresh: '
            'no-token errors=${decoded['errors']}\n',
          );
          return (tokens: null, transient: false);
        }
        // Suwayomi does not rotate refresh tokens; reuse the existing one.
        return (
          tokens: (access: access, refresh: refreshToken),
          transient: false,
        );
      } on SocketException catch (e) {
        logBackgroundRefresh('notify', 'network-error transient=true', e);
        return (tokens: null, transient: true);
      } on TimeoutException catch (e) {
        logBackgroundRefresh('notify', 'timeout transient=true', e);
        return (tokens: null, transient: true);
      } catch (e) {
        logBackgroundRefresh('notify', 'error transient=false', e);
        return (tokens: null, transient: false);
      }
    },
  );
}

Locale _deviceLocale() {
  final locales = PlatformDispatcher.instance.locales;
  return locales.isNotEmpty ? locales.first : const Locale('en');
}
