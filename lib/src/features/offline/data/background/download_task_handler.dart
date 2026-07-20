// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../../../../constants/endpoints.dart';
import '../chapter_download_engine.dart';
import '../offline_download_providers.dart' show pageImageExt;
import '../offline_page_store_io.dart';
import '../offline_paths.dart';
import 'background_completion_log.dart';
import 'background_token_record.dart';
import 'background_work_order.dart';

/// Foreground-service entry point. Must be top-level +
/// `@pragma('vm:entry-point')` so AOT keeps it and the plugin can re-enter it
/// in the background isolate; actual work runs in [DownloadTaskHandler.onStart].
@pragma('vm:entry-point')
void backgroundDownloadCallback() {
  FlutterForegroundTask.setTaskHandler(DownloadTaskHandler());
}

/// Storage key under which the main isolate stashes the JSON-encoded
/// [BackgroundWorkOrder] for the worker to pick up in [DownloadTaskHandler.onStart].
const String kWorkOrderKey = 'work_order';

/// Storage key for the gen-versioned [BackgroundTokenRecord] shared across the
/// main + worker isolates (so a rotated refresh token survives a worker
/// rotation and is read back by the main side on stop).
const String kTokenRecordKey = 'token_record';

/// The background-download worker, running entirely in the foreground-service
/// isolate — plugin-free by design (only `dart:io`, `package:http`, FFT
/// storage/messaging), so it needs no isolate-binary-messenger init.
/// Single-owner: while the queue is non-empty this isolate owns all
/// downloading via the pure-Dart [ChapterDownloadEngine], appending progress
/// to the durable [BackgroundCompletionLog]; `sendDataToMain` events are
/// foreground-only cosmetics.
class DownloadTaskHandler extends TaskHandler {
  /// chapterIds still to download, in order.
  final List<int> _queue = <int>[];

  /// chapterId -> mangaId, needed to build page paths.
  final Map<int, int> _mangaOf = <int, int>{};

  /// chapterId -> download generation, echoed on every event so the main isolate
  /// can drop events from a deleted (stale) generation.
  final Map<int, int> _genOf = <int, int>{};

  /// chapters the main isolate asked to drop (delete/cancel).
  final Set<int> _cancelled = <int>{};

  /// Total chapters seen across this service lifetime (for the notification
  /// "done/total"). Seeded from the work order, grows as `add` ops arrive.
  int _total = 0;

  /// Chapters that reached a terminal state (for the notification counter).
  int _done = 0;

  /// Wi-Fi-only flag carried from the main isolate. v1 LIMITATION: recorded/
  /// live-updated here but not acted on — enforcement is done by the main
  /// isolate; kept for a future in-worker gate.
  // ignore: unused_field
  var _wifiOnly = false;

  /// Set when an `add` op merges new work while the drain loop is between
  /// chapters, so the drain loop re-checks before self-stopping.
  var _sawNewWork = false;

  /// The chapter the drain loop is actively downloading — already pulled off
  /// [_queue], so an `add` merge (which resends every `downloading` row on
  /// resume) would otherwise re-queue and double-download it.
  int? _inFlight;

  /// True once onDestroy fires (timeout / external stop) — the drain loop and
  /// the in-flight chapter observe it and unwind.
  var _stopping = false;

  /// True once the main isolate sends `{op:'pause'}`. The in-flight chapter is
  /// cancelled (left resumable) and the worker self-stops; drift retains
  /// queued/downloading so resume re-enqueues them.
  var _paused = false;

  BackgroundWorkOrder? _order;
  late BackgroundCompletionLog _log;
  late OfflinePaths _paths;
  late IoOfflinePageStore _store;
  late BackgroundTokenRecord _record;
  late TokenBroker _broker;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final raw = await FlutterForegroundTask.getData<String>(key: kWorkOrderKey);
    if (raw == null) {
      // Nothing to do — self-stop so we don't sit as a zombie notification.
      await FlutterForegroundTask.stopService();
      return;
    }
    _order = BackgroundWorkOrder.fromJson(
        jsonDecode(raw) as Map<String, Object?>);
    final order = _order!;

    // Plugin-free path building: the main isolate already resolved the offline
    // base dir (path_provider lives in the root isolate), so we just wrap it.
    _paths = OfflinePaths(order.baseDir);
    _store = IoOfflinePageStore(_paths);
    _log = BackgroundCompletionLog(File('${order.baseDir}/.bg_completion.log'));

    _wifiOnly = order.wifiOnly;
    _record = order.auth;
    _broker = _buildBroker();

    _queue.addAll(order.chapterIds);
    _mangaOf.addAll(order.mangaIdByChapter);
    _genOf.addAll(order.generationByChapter);
    _total = _queue.length;

    await _drain();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    switch (data['op']) {
      case 'add':
        final id = data['chapterId'] as int;
        if (id == _inFlight) break; // already downloading — don't double-queue
        // A re-add after a delete carries a bumped generation; adopt it so this
        // download's events outrank the deleted generation's stale ones.
        _genOf[id] = data['gen'] as int? ?? 0;
        if (!_queue.contains(id) &&
            !_cancelled.contains(id) &&
            !_mangaOf.containsKey(id)) {
          _queue.add(id);
          _mangaOf[id] = data['mangaId'] as int;
          _total++;
          _sawNewWork = true;
        } else if (!_queue.contains(id) && !_cancelled.contains(id)) {
          // Known manga mapping but not currently queued (e.g. re-add of a
          // chapter whose row we still remember): requeue it.
          _queue.add(id);
          _sawNewWork = true;
        }
      case 'remove':
        final id = data['chapterId'] as int;
        _cancelled.add(id);
        _queue.remove(id);
      case 'setWifiOnly':
        _wifiOnly = data['value'] as bool;
      case 'pause':
        // User paused: the in-flight chapter's isCancelled picks this up and
        // unwinds (left resumable), the drain loop exits and self-stops; main
        // won't restart while the persisted pause flag is set.
        _paused = true;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // The drain loop + the in-flight chapter both observe this and unwind. The
    // log is flushed per page, so nothing is lost on an abrupt stop.
    _stopping = true;
  }

  // ---------------------------------------------------------------------------
  // Drain loop
  // ---------------------------------------------------------------------------

  Future<void> _drain() async {
    while (!_stopping && !_paused) {
      final next = _queue.where((c) => !_cancelled.contains(c)).firstOrNull;
      if (next == null) {
        if (_sawNewWork) {
          _sawNewWork = false;
          continue;
        }
        // Queue genuinely empty — record the drain marker, tell main we're
        // stopping (so it can recheck for anything enqueued during this window
        // and restart us), then self-stop.
        await _log.appendDrained();
        FlutterForegroundTask.sendDataToMain({'kind': 'drained'});
        await FlutterForegroundTask.stopService();
        return;
      }
      _queue.remove(next);
      _inFlight = next;
      final parked = await _downloadChapter(next, _mangaOf[next]!);
      _inFlight = null;
      if (parked) {
        // Server unreachable — stop with the queue still in drift so a reconnect
        // (or relaunch) resumes it. No drained marker: it isn't drained, parked.
        await FlutterForegroundTask.stopService();
        return;
      }
    }
    // Exited because the user paused (not a stop/timeout): self-stop cleanly to
    // clear the FGS notification. drift still has queued/downloading rows, so
    // resume just re-enqueues; do NOT append a drained marker — this is parked,
    // not drained.
    if (_paused && !_stopping) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Returns true when the chapter was parked (server unreachable) — the drain
  /// should stop and leave the queue intact for a later resume.
  Future<bool> _downloadChapter(int chapterId, int mangaId) async {
    final urls = await _resolvePageUrls(chapterId);
    if (urls == null) {
      // Server unreachable resolving pages: leave `downloading` (resumable) and
      // park. Marking it error here poisoned the whole queue — one blip
      // cascaded through every remaining chapter.
      return true;
    }
    if (urls.isEmpty) {
      // Could not resolve pages (terminal): a server with no pages or a hard
      // failure even after a token refresh. Mark error, keep draining.
      await _log.appendChapter(
          chapterId: chapterId,
          status: 'error',
          pages: 0,
          bytes: 0,
          generation: _genOf[chapterId] ?? 0);
      _done++;
      _afterChapter(chapterId, 'error');
      return false;
    }

    // Tell the UI this chapter is downloading so the progress arc shows in
    // foreground (the main isolate applies it to the catalog); while
    // backgrounded it's dropped and covered by log replay.
    FlutterForegroundTask.sendDataToMain({
      'kind': 'chapterStart',
      'chapterId': chapterId,
      'gen': _genOf[chapterId] ?? 0,
      // The resolved page count — lets the UI show a determinate progress arc
      // (webtoon chapters don't know their page total until resolved here).
      'total': urls.length,
    });

    final engine = _buildEngine();
    final pages = [
      for (var i = 0; i < urls.length; i++) (index: i, url: urls[i]),
    ];
    final outcome = await engine.download(
      mangaId: mangaId,
      chapterId: chapterId,
      pages: pages,
      isCancelled: () => _cancelled.contains(chapterId) || _stopping || _paused,
      onPageStored: (i, rel, bytes) {
        // Live per-page progress for the foreground UI (drift row applied by the
        // main isolate). The durable record is still the completion log.
        FlutterForegroundTask.sendDataToMain({
          'kind': 'page',
          'chapterId': chapterId,
          'gen': _genOf[chapterId] ?? 0,
          'pageIndex': i,
          'relPath': rel,
        });
        return _log.appendPage(
          chapterId: chapterId,
          mangaId: mangaId,
          pageIndex: i,
          relPath: rel,
          bytes: bytes,
          generation: _genOf[chapterId] ?? 0,
        );
      },
    );

    final String? status = outcome.succeeded
        ? 'downloaded'
        : outcome.offline
            ? 'offline'
            : outcome.authFailed
                ? 'authFailed'
                // cancelled → no terminal line; leave it `downloading` so a
                // later replay/worker can pick it up (delete cleans it up).
                : outcome.cancelled
                    ? null
                    : 'error';

    if (status != null) {
      final bytes = await _store.chapterBytes(mangaId, chapterId);
      await _log.appendChapter(
        chapterId: chapterId,
        status: status,
        pages: urls.length,
        bytes: bytes,
        generation: _genOf[chapterId] ?? 0,
      );
      _done++;
    }
    _afterChapter(chapterId, status);
    // Network died mid-download: the chapter is recorded `offline` (resumable),
    // so park rather than churn every remaining chapter through the same drop.
    return status == 'offline';
  }

  /// Notification + main-isolate notification after each chapter settles.
  void _afterChapter(int chapterId, String? status) {
    FlutterForegroundTask.sendDataToMain({
      'kind': 'chapterDone',
      'chapterId': chapterId,
      'gen': _genOf[chapterId] ?? 0,
      'status': status,
    });
    FlutterForegroundTask.updateService(
      notificationTitle: 'Downloading chapters',
      notificationText: 'Downloading — $_done/$_total',
    );
  }

  // ---------------------------------------------------------------------------
  // Page-list resolution (hand-rolled GraphQL POST, pure http)
  // ---------------------------------------------------------------------------

  /// Resolves a chapter's page URLs: the list on success, empty on terminal
  /// failure (no pages), or null when the server was unreachable (transient —
  /// the caller parks, doesn't error).
  Future<List<String>?> _resolvePageUrls(int chapterId) async {
    var result = await _postChapterPages(chapterId, _record.accessToken);
    if (result == _gqlAuthError && _record.authType == 'uiLogin') {
      final newAccess = await _broker.resolveAfter401(_record.accessToken ?? '');
      if (newAccess != null) {
        result = await _postChapterPages(chapterId, newAccess);
      }
    }
    if (result is List<String>) return result;
    if (result == _gqlNetworkError) return null; // transient — park
    return const <String>[]; // terminal
  }

  /// Sentinel returned by [_postChapterPages] to signal an auth (401/403)
  /// failure distinctly from "no pages / other error" (an empty list).
  static const Object _gqlAuthError = Object();

  /// Sentinel: the page-list POST couldn't reach the server (transient),
  /// distinct from an empty (terminal) result — so a network blip parks the
  /// chapter instead of erroring and poisoning the queue.
  static const Object _gqlNetworkError = Object();

  /// Returns the page-URL list on success, [_gqlAuthError] on 401/403, or an
  /// empty list on any other failure.
  Future<Object> _postChapterPages(int chapterId, String? accessToken) async {
    final order = _order!;
    final endpoint = Endpoints.baseApi(
      baseUrl: order.serverBase,
      port: order.port,
      addPort: order.addPort,
      isGraphQl: true,
    );
    final headers = <String, String>{'Content-Type': 'application/json'};
    _applyAuthHeaders(headers, accessToken);
    final body = jsonEncode({
      'query':
          'mutation GetChapterPages(\$input: FetchChapterPagesInput!){ fetchChapterPages(input: \$input){ pages } }',
      'variables': {
        'input': {'chapterId': chapterId},
      },
    });
    try {
      final res = await http.post(Uri.parse(endpoint),
          headers: headers, body: body);
      if (res.statusCode == 401 || res.statusCode == 403) return _gqlAuthError;
      if (res.statusCode != 200) return const <String>[];
      final decoded = jsonDecode(res.body) as Map<String, Object?>;
      final data = decoded['data'] as Map<String, Object?>?;
      final fetch = data?['fetchChapterPages'] as Map<String, Object?>?;
      final pages = fetch?['pages'];
      if (pages is List) return pages.cast<String>();
      return const <String>[];
    } on SocketException {
      return _gqlNetworkError; // transient — park, don't error
    } catch (_) {
      return const <String>[];
    }
  }

  /// Applies the in-isolate auth to a GraphQL/REST request's headers, mirroring
  /// the app's auth modes (uiLogin Bearer, basic, simpleLogin cookie).
  void _applyAuthHeaders(Map<String, String> headers, String? accessToken) {
    switch (_record.authType) {
      case 'uiLogin':
        if (accessToken != null && accessToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $accessToken';
        }
      case 'basic':
        final cred = _record.basicCredential;
        if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
      case 'simpleLogin':
        final cookie = _record.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    }
  }

  // ---------------------------------------------------------------------------
  // Engine wiring (in-isolate deps)
  // ---------------------------------------------------------------------------

  ChapterDownloadEngine _buildEngine() => ChapterDownloadEngine(
        writePage: _store,
        parallelPageLimit: 5,
        fetchPage: (pageUrl) async {
          final (url, headers) = _authedPageRequest(pageUrl);
          final http.Response res;
          try {
            res = await http.get(Uri.parse(url), headers: headers);
          } on SocketException {
            // Device offline (connection refused / unreachable host / DNS).
            throw const PageOfflineException();
          }
          if (res.statusCode == 401 || res.statusCode == 403) {
            throw const PageAuthException();
          }
          if (res.statusCode != 200) {
            throw Exception('page fetch failed ($pageUrl): ${res.statusCode}');
          }
          return (
            bytes: res.bodyBytes,
            ext: pageImageExt(res.headers['content-type'], res.bodyBytes),
          );
        },
        refreshAuth: () async {
          // Only ui_login rotates; basic/simple credentials are static.
          if (_record.authType != 'uiLogin') return false;
          final newAccess =
              await _broker.resolveAfter401(_record.accessToken ?? '');
          return newAccess != null;
        },
      );

  /// Builds the page-image GET URL + headers, mirroring
  /// `fetchOfflinePageBytes`: base API without `/api` (page URLs already carry
  /// it), ui_login as `?token=`, basic/simpleLogin via headers. Reads the
  /// current in-isolate [_record] (kept fresh by the broker), not Riverpod.
  (String, Map<String, String>) _authedPageRequest(String pageUrl) {
    final order = _order!;
    final base = Endpoints.baseApi(
      baseUrl: order.serverBase,
      port: order.port,
      addPort: order.addPort,
      appendApiToUrl: false,
    );
    var fetchUrl = '$base$pageUrl';
    final headers = <String, String>{};
    switch (_record.authType) {
      case 'basic':
        final cred = _record.basicCredential;
        if (cred != null && cred.isNotEmpty) headers['Authorization'] = cred;
      case 'simpleLogin':
        final cookie = _record.simpleCookie;
        if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
      case 'uiLogin':
        final token = _record.accessToken;
        if (token != null && token.isNotEmpty) {
          final sep = fetchUrl.contains('?') ? '&' : '?';
          fetchUrl = '$fetchUrl${sep}token=${Uri.encodeQueryComponent(token)}';
        }
    }
    return (fetchUrl, headers);
  }

  // ---------------------------------------------------------------------------
  // Token broker (in-isolate, FFT-storage-backed)
  // ---------------------------------------------------------------------------

  TokenBroker _buildBroker() => TokenBroker(
        read: () async {
          final raw =
              await FlutterForegroundTask.getData<String>(key: kTokenRecordKey);
          if (raw == null) return _record;
          _record = BackgroundTokenRecord.fromJson(
              jsonDecode(raw) as Map<String, Object?>);
          return _record;
        },
        write: (r) async {
          _record = r;
          await FlutterForegroundTask.saveData(
              key: kTokenRecordKey, value: jsonEncode(r.toJson()));
        },
        refreshFn: (refreshToken) async {
          // Only ui_login refreshes; basic/simple return null.
          if (_record.authType != 'uiLogin') return null;
          final order = _order!;
          final endpoint = Endpoints.baseApi(
            baseUrl: order.serverBase,
            port: order.port,
            addPort: order.addPort,
            isGraphQl: true,
          );
          final body = jsonEncode({
            'query':
                'mutation RefreshToken(\$input: RefreshTokenInput!){ refreshToken(input: \$input){ accessToken } }',
            'variables': {
              'input': {'refreshToken': refreshToken},
            },
          });
          try {
            final res = await http.post(
              Uri.parse(endpoint),
              headers: const {'Content-Type': 'application/json'},
              body: body,
            );
            if (res.statusCode != 200) return null;
            final decoded = jsonDecode(res.body) as Map<String, Object?>;
            final data = decoded['data'] as Map<String, Object?>?;
            final refreshed =
                data?['refreshToken'] as Map<String, Object?>?;
            final access = refreshed?['accessToken'] as String?;
            if (access == null || access.isEmpty) return null;
            // Suwayomi's refresh doesn't rotate the refresh token, so reuse the
            // input one (the broker persists it back as the current refresh).
            return (access: access, refresh: refreshToken);
          } catch (_) {
            return null;
          }
        },
      );
}
