// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../../constants/endpoints.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../offline/data/background/background_token_record.dart';
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
  final store = await NotificationStateStore.open();
  final config = store.readConfig();
  final token = store.readTokenRecord();
  if (config == null || token == null) return true;

  final l10n = lookupAppLocalizations(_deviceLocale());
  final notifier = LocalNotificationService();
  await notifier.init(onBackgroundTap: notificationActionCallback);
  final client = NotificationBackgroundClient(
    endpoint: config.endpoint,
    record: token,
    broker: _brokerFor(store, config.endpoint),
  );

  var ok = true;
  if (config.newChaptersEnabled) {
    ok = await _runNewChapters(store, config, client, notifier, l10n);
  }
  if (config.appUpdatesEnabled) {
    await _checkAppUpdate(store, config, client, notifier, l10n);
  }
  if (config.extensionUpdatesEnabled) {
    await _checkExtensionUpdates(store, client, notifier, l10n);
  }
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
        config.serverId, NewChapterWatermark(fetchedAt: maxFetched));
    return true;
  }

  // 2. Paginate the overlap window to exhaustion.
  final gte =
      (watermark.fetchedAt - kDefaultOverlapMs).clamp(0, watermark.fetchedAt);
  final all = <NotifChapter>[];
  final mangaCategories = <int, Set<int>>{};
  String? after;
  while (true) {
    final page =
        await client.fetchNewChaptersPage(fetchedAtGte: '$gte', after: after);
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
          fetchedAt: n.fetchedAt
        ),
    ],
    watermark: watermark,
    allowedMangaIds: config.allowedMangaIds(mangaCategories),
  );

  if (result.groups.isEmpty) {
    await store.writeWatermark(config.serverId, result.watermark);
    return true;
  }

  // 4. Durable outbox BEFORE publishing.
  final byId = {for (final n in all) n.id: n};
  final pending = [
    for (final g in result.groups) _toPending(g, byId),
  ];
  await store.writeOutbox(
      NotificationOutbox(pending: pending, nextWatermark: result.watermark));

  // 5. Publish, then mark delivered (advance cursor + clear outbox).
  await _publish(notifier, client, l10n, config, pending);
  await store.writeWatermark(config.serverId, result.watermark);
  await store.clearOutbox();
  return true;
}

PendingSeriesNotification _toPending(
    MangaNewChapters group, Map<int, NotifChapter> byId) {
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
    series.add(SeriesNotificationContent(
      mangaId: p.mangaId,
      title: p.mangaTitle,
      body: _describe(l10n, p),
      firstChapterId: p.firstChapterId,
      chapterIds: p.chapterIds,
      coverPath: config.hideContent ? null : await _fetchCover(client, p),
    ));
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
Future<void> handleNotificationAction(
    String? actionId, String? payload) async {
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
    NotificationBackgroundClient client, PendingSeriesNotification p) async {
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
    GenericNewChapters(:final count) =>
      l10n.notificationChaptersGeneric(count),
    SingleNewChapter(:final number, :final more) => more == 0
        ? l10n.notificationChapterSingle(number)
        : l10n.notificationChapterSingleAndMore(number, more),
    MultipleNewChapters(:final numbers, :final more) => more == 0
        ? l10n.notificationChaptersMultiple(numbers.join(', '))
        : l10n.notificationChaptersMultipleAndMore(numbers.join(', '), more),
  };
}

/// A [TokenBroker] backed by the persistent store, so a ui_login refresh in the
/// worker isolate rotates the shared record (same gen-versioned scheme the
/// download worker uses).
TokenBroker _brokerFor(NotificationStateStore store, NotificationEndpoint ep) =>
    TokenBroker(
      read: () async =>
          store.readTokenRecord() ??
          const BackgroundTokenRecord(gen: 0, authType: 'none'),
      write: (r) => store.writeTokenRecord(r),
      refreshFn: (refreshToken) async {
        final endpoint = Endpoints.baseApi(
          baseUrl: ep.baseUrl,
          port: ep.port,
          addPort: ep.addPort,
          isGraphQl: true,
        );
        try {
          final res = await http.post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query':
                  r'mutation RefreshToken($input: RefreshTokenInput!){ refreshToken(input: $input){ accessToken } }',
              'variables': {
                'input': {'refreshToken': refreshToken},
              },
            }),
          );
          if (res.statusCode != 200) return null;
          final data = (jsonDecode(res.body) as Map<String, Object?>)['data']
              as Map<String, Object?>?;
          final access =
              (data?['refreshToken'] as Map<String, Object?>?)?['accessToken']
                  as String?;
          if (access == null || access.isEmpty) return null;
          // Suwayomi doesn't rotate the refresh token — reuse it.
          return (access: access, refresh: refreshToken);
        } catch (_) {
          return null;
        }
      },
    );

Locale _deviceLocale() {
  final locales = PlatformDispatcher.instance.locales;
  return locales.isNotEmpty ? locales.first : const Locale('en');
}
