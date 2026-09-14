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
import '../../../offline/data/background/background_chapter_fetch.dart';
import '../../../offline/data/background/background_download_lock.dart';
import '../../../offline/data/background/background_schedule.dart';
import '../../../offline/data/background/background_token_record.dart';
import '../../../offline/data/background/catchup_download_executor.dart';
import '../../../offline/data/background/catchup_work_spec.dart';
import '../../domain/new_chapter_detection.dart';
import '../local_notification_service.dart';
import '../notification_state_store.dart';
import 'notification_background_client.dart';

/// The headless new-chapter check: read config + cursor, paginate the server's
/// unread/in-library delta, detect what's new, write a durable outbox, publish,
/// then advance the cursor. Returns false only on a transient failure so the
/// scheduler retries (a cursor is never advanced past unseen chapters).
///
/// Runs in the WorkManager isolate — no Riverpod, no BuildContext.
Future<bool> runNewChapterCheck() async {
  // The main isolate wires this up in main.dart; a WorkManager run gets a
  // fresh isolate every time and starts with no diagnostic sink at all, so
  // without this, every recordDiagnostic() call in the download/catch-up
  // path this function calls into is a silent no-op — invisible even though
  // the same crash-log file (and its Settings copy action) is what the user
  // actually checks.
  final crashLogPath = await initCrashLog();
  setDiagnosticSink((line) => writeCrashLog(crashLogPath, line));

  final store = await NotificationStateStore.open();
  final config = store.readConfig();
  final token = store.readTokenRecord();
  if (config == null || token == null) {
    // The only way to tell "the OS never woke this task" apart from "it woke
    // but had nothing configured yet" from the field — both look identical
    // (a silent gap in the log) without this line.
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
  final client = NotificationBackgroundClient(
    endpoint: config.endpoint,
    record: token,
    broker: _brokerFor(store, config.endpoint),
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
    ok = await _runNewChapters(store, config, client, notifier, l10n);
  }
  // Background download step — own cursor, keep-rule scope, no category
  // filter. Resolution records the obligations; the executor then downloads
  // as many as the run's budget allows — unless the user only wants
  // detection in the background and prefers to fetch files in the foreground.
  if (catchupStore.enabled &&
      !catchupStore.paused &&
      catchupStore.matchesIdentity(config) &&
      (!(catchupStore.readSpec()?.wifiOnly ?? true) || unmetered)) {
    ok = await _runDownloadResolution(catchupStore, config, client) && ok;
  }
  if (!catchupStore.paused &&
      ((catchupStore.enabled && catchupStore.downloadEnabled) ||
          (catchupStore.readSpec()?.queuedChapters.isNotEmpty ?? false))) {
    ok =
        await runCatchupDownloads(
          catchupStore: catchupStore,
          config: config,
          record: client.currentRecord,
          broker: client.broker,
        ) &&
        ok;
  }
  if (notificationPolicy && config.appUpdatesEnabled) {
    await _checkAppUpdate(store, config, client, notifier, l10n);
  }
  if (notificationPolicy && config.extensionUpdatesEnabled) {
    await _checkExtensionUpdates(store, client, notifier, l10n);
  }
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-worker: '
    'check-finished ok=$ok\n',
  );
  return ok;
}

/// App-update check — compares the latest GitHub release to the installed
/// version, notifying once per new version.
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
  if (release.version == store.lastNotifiedAppVersion) return; // already told
  await store.setLastNotifiedAppVersion(release.version);
  await notifier.showAppUpdate(
    l10n.notificationAppUpdateTitle,
    l10n.notificationAppUpdateBody(release.version),
    release.url.isEmpty ? null : release.url,
  );
}

/// Extension-update check — notifies when the count of installed extensions with
/// an update rises (server-tracked).
Future<void> _checkExtensionUpdates(
  NotificationStateStore store,
  NotificationBackgroundClient client,
  LocalNotificationService notifier,
  AppLocalizations l10n,
) async {
  final count = await client.countExtensionUpdates();
  if (count <= store.lastExtensionUpdateCount) {
    // Fewer/equal — user updated some or nothing new; just record.
    await store.setLastExtensionUpdateCount(count);
    return;
  }
  await store.setLastExtensionUpdateCount(count);
  await notifier.showExtensionUpdates(
    l10n.notificationExtensionUpdateTitle,
    l10n.notificationExtensionUpdateBody(count),
  );
}

Future<bool> _runNewChapters(
  NotificationStateStore store,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
  LocalNotificationService notifier,
  AppLocalizations l10n,
) async {
  // 0. Crash recovery — an outbox present means a prior run posted (or died
  // mid-post) without advancing the cursor. Re-publish (stable ids → replace,
  // not re-buzz), advance, clear.
  final stranded = store.readOutbox();
  if (stranded != null) {
    await _publish(notifier, client, l10n, config, stranded.pending);
    await store.writeWatermark(config.serverId, stranded.nextWatermark);
    await store.clearOutbox();
  }

  var watermark = store.readWatermark(config.serverId);

  // 1. First enable: seed the cursor to the server's current max fetch time and
  // notify nothing, so we don't dump the backlog.
  if (watermark.fetchedAt == 0 && watermark.recent.isEmpty) {
    final maxFetched = await client.serverMaxFetchedAt();
    await store.writeWatermark(
      config.serverId,
      NewChapterWatermark(fetchedAt: maxFetched),
    );
    return true;
  }

  // 2. Paginate the overlap window to exhaustion.
  final gte = (watermark.fetchedAt - kDefaultOverlapMs).clamp(
    0,
    watermark.fetchedAt,
  );
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

  // 3. Detect.
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
    allowedMangaIds: config.allowedMangaIds(mangaCategories),
  );

  // The notify list this pass will actually surface, per manga. Paired with the
  // download side's `offline-download-resolve` line, this is how you tell
  // "notified but not downloaded" apart: a manga appearing here but not in the
  // download pass's `queued` (and showing up in its `droppedOutOfScope`) was
  // notified yet is outside the background download scope.
  final notifyList = [
    for (final g in result.groups)
      '${g.mangaId}:${g.chapters.map((c) => c.id).join('|')}',
  ].join(',');
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] offline-notify: detected '
    'candidates=${all.length} groups=${result.groups.length} '
    'notify=[$notifyList]\n',
  );

  if (result.groups.isEmpty) {
    await store.writeWatermark(config.serverId, result.watermark);
    return true;
  }

  // 4. Durable outbox BEFORE publishing.
  final byId = {for (final n in all) n.id: n};
  final pending = [for (final g in result.groups) _toPending(g, byId)];
  await store.writeOutbox(
    NotificationOutbox(pending: pending, nextWatermark: result.watermark),
  );

  // 5. Publish, then mark delivered (advance cursor + clear outbox).
  await _publish(notifier, client, l10n, config, pending);
  await store.writeWatermark(config.serverId, result.watermark);
  await store.clearOutbox();
  return true;
}

/// The download side of detection. Same pagination and detector as the notify
/// step but consuming its OWN cursor, scoped to the spec's keep-rule manga and
/// never the notification category filter — muting a category must not
/// silently stop its downloads.
Future<bool> _runDownloadResolution(
  CatchupStateStore catchupStore,
  NotificationWorkerConfig config,
  NotificationBackgroundClient client,
) async {
  final support = await getApplicationSupportDirectory();
  final lock = BackgroundDownloadLock(File('${support.path}/offline/.bg_lock'));
  if (!await lock.acquire('resolve')) return true;
  try {
    await catchupStore.reload();
    if (catchupStore.paused || !catchupStore.matchesIdentity(config)) {
      return true;
    }
    final spec = catchupStore.readSpec();
    if (spec == null || spec.manga.isEmpty) return true;
    // The worker must not outlive its world: after a server switch the spec is
    // dead until the foreground rewrites it.
    if (spec.serverId != catchupStore.catalogServerId) return true;

    if (!await verifyBackgroundServerIdentity(
      target: BackgroundServerTarget(
        serverBase: config.endpoint.baseUrl,
        port: config.endpoint.port,
        addPort: config.endpoint.addPort,
      ),
      record: client.currentRecord,
      broker: client.broker,
      expected: spec.serverId,
    ).timeout(const Duration(seconds: 10), onTimeout: () => false)) {
      return true;
    }

    var ledger = catchupStore.readLedger(spec.serverId);

    // First enable: seed to now. The toggle does not backfill history — the
    // foreground launch pass owns the backlog.
    if (ledger.cursor.fetchedAt == 0 && ledger.cursor.recent.isEmpty) {
      final maxFetched = await client.serverMaxFetchedAt();
      if (await lock.yieldRequested()) return true;
      await catchupStore.writeLedger(
        spec.serverId,
        ledger.copyWith(cursor: NewChapterWatermark(fetchedAt: maxFetched)),
      );
      return true;
    }

    final gte = (ledger.cursor.fetchedAt - kDefaultOverlapMs).clamp(
      0,
      ledger.cursor.fetchedAt,
    );
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

    // Fresh detections whose manga carries no keep rule in the spec: they are
    // dropped from the download plan here, even though the notify pass (scoped
    // by the category filter, not this one) may have just surfaced them. A
    // non-empty list for a series you expect kept means the spec — a foreground
    // snapshot built from libraryManga() — is stale or dropped that manga while
    // it still carries a rule (e.g. inLibraryAt='0' desync). This is the exact
    // signature of "notified but never downloaded".
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
    final droppedList =
        droppedOutOfScope.entries.map((e) => '${e.value}:${e.key}').join(',');
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-download-resolve: '
      'candidates=${all.length} queued=[$queuedList] '
      'droppedOutOfScope=[$droppedList]\n',
    );

    // Obligations and the advanced cursor land in ONE atomic write: the cursor
    // may only move once every detected chapter is owed somewhere.
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

Future<void> _publish(
  LocalNotificationService notifier,
  NotificationBackgroundClient client,
  AppLocalizations l10n,
  NotificationWorkerConfig config,
  List<PendingSeriesNotification> pending,
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
        coverPath: config.hideContent ? null : await _fetchCover(client, p),
      ),
    );
  }
  await notifier.showNewChapters(
    summaryTitle: summaryTitle,
    summaryText: summaryText,
    summaryLines: [for (final p in pending) p.mangaTitle],
    hideContent: config.hideContent,
    markReadLabel: l10n.notificationActionMarkRead,
    viewLabel: l10n.notificationActionView,
    downloadLabel: l10n.notificationActionDownload,
    series: series,
  );
}

/// Isolate entry point for a Mark-read / Download action fired while the app is
/// dead. Top-level + `vm:entry-point` so the OS can spawn it.
@pragma('vm:entry-point')
void notificationActionCallback(NotificationResponse response) {
  handleNotificationAction(response.actionId, response.payload);
}

/// Handles a Mark-read / Download notification action headlessly (the app may be
/// dead): reads config + token, builds a client, fires the mutation. View is a
/// UI action, routed by the foreground handler instead.
Future<void> handleNotificationAction(String? actionId, String? payload) async {
  if (actionId != kNotifActionMarkRead && actionId != kNotifActionDownload) {
    return;
  }
  final p = NotificationPayload.decode(payload);
  if (p.chapterIds.isEmpty) return;
  final store = await NotificationStateStore.open();
  final config = store.readConfig();
  final token = store.readTokenRecord();
  if (config == null || token == null) return;
  final client = NotificationBackgroundClient(
    endpoint: config.endpoint,
    record: token,
    broker: _brokerFor(store, config.endpoint),
  );
  if (actionId == kNotifActionMarkRead) {
    await client.markRead(p.chapterIds);
  } else {
    await client.enqueueDownloads(p.chapterIds);
  }
}

/// Fetch + cache a series cover to a temp file for the notification's
/// BigPicture. Best-effort — null on any failure falls back to text.
Future<String?> _fetchCover(
  NotificationBackgroundClient client,
  PendingSeriesNotification p,
) async {
  final url = p.thumbnailUrl;
  if (url == null || url.isEmpty) return null;
  try {
    final bytes = await client.fetchCover(url);
    if (bytes == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/notif_cover_${p.mangaId}.jpg');
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

/// A [TokenBroker] backed by the persistent store, so a ui_login refresh in the
/// worker isolate rotates the shared record (same gen-versioned scheme the
/// download worker uses).
TokenBroker _brokerFor(NotificationStateStore store, NotificationEndpoint ep) {
  final epoch = store.readConfig()?.identityEpoch;
  return TokenBroker(
    read: () async =>
        store.readTokenRecord() ??
        const BackgroundTokenRecord(gen: 0, authType: 'none'),
    write: (r) => withBackgroundScheduleLock(() async {
      final currentStore = await NotificationStateStore.open();
      final current = currentStore.readTokenRecord();
      final controls = await CatchupStateStore.open();
      if (controls.identityAuthorized &&
          currentStore.readConfig()?.identityEpoch == epoch &&
          current?.endpoint == r.endpoint &&
          current?.refreshToken == r.refreshToken &&
          current?.authType == r.authType &&
          r.gen > (current?.gen ?? -1)) {
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
      // Read fresh: the token record and its headers travel together.
      Map<String, String> extraHeaders = const {};
      try {
        extraHeaders = store.readTokenRecord()?.extraHeaders ?? const {};
      } catch (_) {}
      try {
        final res = await http
            .post(
              Uri.parse(endpoint),
              headers: applyIsolateCustomHeaders(
                {'Content-Type': 'application/json'},
                extraHeaders,
              ),
              body: jsonEncode({
                'query':
                    r'mutation RefreshToken($input: RefreshTokenInput!){ refreshToken(input: $input){ accessToken } }',
                'variables': {
                  'input': {'refreshToken': refreshToken},
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        // A proxy answering for a dead origin is the server being
        // unreachable, not the refresh token being invalid — without this,
        // the first request after reconnecting (racing the network
        // actually settling) permanently condemns every chapter that
        // happened to 401 in that window.
        if (isGatewayStatus(res.statusCode)) {
          return (tokens: null, transient: true);
        }
        if (res.statusCode != 200) {
          // The server was reached and rejected the refresh (e.g. 401/403 =
          // refresh token no longer accepted). This is the decisive line for
          // "the background worker worked once then fails every wake": if it
          // shows up, the fix is on the auth side, not Doze/scheduling.
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
          // HTTP 200 but no token — usually a GraphQL `errors` payload
          // (invalid/expired refresh token reported in-band). Surface the
          // errors so the reason is visible in the log.
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-refresh: '
            'no-token errors=${decoded['errors']}\n',
          );
          return (tokens: null, transient: false);
        }
        // Suwayomi doesn't rotate the refresh token — reuse it.
        return (
          tokens: (access: access, refresh: refreshToken),
          transient: false,
        );
      } on SocketException {
        return (tokens: null, transient: true);
      } on TimeoutException {
        return (tokens: null, transient: true);
      } catch (_) {
        return (tokens: null, transient: false);
      }
    },
  );
}

Locale _deviceLocale() {
  final locales = PlatformDispatcher.instance.locales;
  return locales.isNotEmpty ? locales.first : const Locale('en');
}
