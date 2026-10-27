// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/endpoints.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/crash/crash_log.dart';
import '../../../../utils/crash/diagnostics.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/network/gateway_status.dart';
import '../../../account/data/account_permission.dart';
import '../../../auth/data/secure_credentials_provider.dart';
import '../chapter_download_engine.dart';
import '../chapter_manifest.dart';
import '../offline_download_providers.dart' show pageImageExt;
import '../offline_page_store_io.dart';
import '../offline_paths.dart';
import '../offline_server_identity.dart';
import '../offline_storage_identity.dart';
import 'background_chapter_fetch.dart';
import 'background_completion_log.dart';
import 'background_download_lock.dart';
import 'background_endpoint.dart';
import 'background_token_record.dart';
import 'background_work_order.dart';
import 'catchup_work_spec.dart';
import 'record_seal.dart';
import 'work_order_admission.dart';

// Top-level entry point and pragma keep the AOT callback available to the background plugin.
@pragma('vm:entry-point')
void backgroundDownloadCallback() {
  FlutterForegroundTask.setTaskHandler(DownloadTaskHandler());
}

// Bound HTTP waits so an unresponsive proxy cannot strand the worker on one await.
const _httpTimeout = Duration(seconds: 30);

const String kWorkOrderKey = 'work_order';

/// Shared gen-versioned token record; main reads back worker-rotated tokens on stop.
const String kTokenRecordKey = 'token_record';

class DownloadTaskHandler extends TaskHandler {
  final Set<int> _queue = <int>{};

  final Map<int, int> _mangaOf = <int, int>{};

  // Stamp every event so main can reject pre-delete generations.
  final Map<int, int> _genOf = <int, int>{};

  final Set<int> _cancelled = <int>{};

  int _total = 0;

  int _done = 0;

  var _wifiOnly = false;

  // New work arriving between chapters must be observed before self-stop.
  var _sawNewWork = false;

  // In-flight work has left the queue; exclude it when merging resumed drift rows.
  int? _inFlight;

  var _stopping = false;
  Future<void>? _drainFuture;
  Timer? _yieldTimer;
  bool _ownsLock = false;
  Future<void>? _controlCheck;
  DateTime? _lastControlRefresh;

  var _paused = false;

  // Reuse connections across the worker run instead of paying TLS setup per page.
  final http.Client _http = http.Client();

  BackgroundWorkOrder? _order;

  void _sendEvent(Map<String, Object?> data) {
    FlutterForegroundTask.sendDataToMain({
      ...data,
      'catalogServerId': _order?.catalogServerId,
      'identityEpoch': _order?.identityEpoch,
      'attemptId': _order?.attemptId,
    });
  }

  BackgroundDownloadLock? _lock;
  late BackgroundCompletionLog _log;
  late OfflinePaths _paths;
  late IoOfflinePageStore _store;
  late BackgroundTokenRecord _record;
  late TokenBroker _broker;

  late String _serverBase;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // The worker isolate does not inherit the main diagnostic sink.
    try {
      final crashLogPath = await initCrashLog();
      setDiagnosticSink((line) => writeCrashLog(crashLogPath, line));
    } catch (_) {}
    await RecordSeal.load(kSecureStorage);
    final raw = await FlutterForegroundTask.getData<String>(key: kWorkOrderKey);
    if (raw == null) {
      _sendEvent({'kind': 'noWorkOrder', 'starter': starter.name});
      await FlutterForegroundTask.stopService();
      return;
    }
    _order = BackgroundWorkOrder.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
    var order = _order!;

    // path_provider runs on the root isolate; the work order supplies its resolved path.
    _paths = OfflinePaths(order.baseDir);
    _store = IoOfflinePageStore(_paths);
    _log = BackgroundCompletionLog(File('${order.baseDir}/.bg_completion.log'));

    _wifiOnly = order.wifiOnly;

    _lock = BackgroundDownloadLock(File('${order.baseDir}/.bg_lock'));
    var acquired = await _lock!.acquire('fgs');
    if (!acquired) {
      await _lock!.requestYield();
      for (var i = 0; i < 15 && !acquired; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        acquired = await _lock!.acquire('fgs');
        if (!acquired) await _lock!.requestYield();
      }
    }
    if (!acquired) {
      _sendEvent({'kind': 'lockFailed'});
      await FlutterForegroundTask.stopService();
      return;
    }

    _ownsLock = true;
    BackgroundWorkOrder? admitted;
    try {
      admitted = await withWorkOrderAdmission(order.baseDir, () async {
        final current = decodeWorkOrder(
          await FlutterForegroundTask.getData<String>(key: kWorkOrderKey),
        );
        if (current == null ||
            current.attemptId != order.attemptId ||
            !await _controlsAllow(current)) {
          return null;
        }
        if (_stopping || !_ownsLock) return null;
        if (current.attemptId != null) {
          final saved = await FlutterForegroundTask.saveData(
            key: kAcceptedWorkOrderKey,
            value: current.attemptId!,
          );
          if (!saved) throw StateError('Could not claim download work order');
        }
        return current;
      });
    } catch (error) {
      await _releaseOwnership();
      _sendEvent({'kind': 'lockFailed', 'error': '$error'});
      await FlutterForegroundTask.stopService();
      return;
    }
    if (admitted == null || _stopping || _paused) {
      await _releaseOwnership();
      await FlutterForegroundTask.stopService();
      return;
    }
    order = admitted;
    _order = admitted;
    _record = order.auth;
    _broker = _buildBroker();
    _serverBase = await pickBackgroundServerBase(
      active: order.serverBase,
      lanUrl: order.lanUrl,
      externalUrl: order.externalUrl,
      source: 'download',
    );
    _sendEvent({'kind': 'owned', 'attemptId': order.attemptId});

    _queue.addAll(order.chapterIds);
    _mangaOf.addAll(order.mangaIdByChapter);
    for (final entry in order.generationByChapter.entries) {
      if (entry.value > (_genOf[entry.key] ?? -1)) {
        _genOf[entry.key] = entry.value;
      }
    }
    _total = _queue.length;

    _yieldTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _controlCheck ??= _checkControls().whenComplete(
        () => _controlCheck = null,
      );
    });
    _drainFuture = _verifyAndDrain(order);
    try {
      await _drainFuture;
    } catch (error) {
      _sendEvent({'kind': 'parked', 'reason': '$error'});
      await _releaseOwnership();
      await FlutterForegroundTask.stopService();
    } finally {
      _yieldTimer?.cancel();
    }
  }

  Future<void> _verifyAndDrain(BackgroundWorkOrder order) async {
    await _checkControls();
    if (!_paused &&
        !_stopping &&
        !await verifyBackgroundServerIdentity(
          target: BackgroundServerTarget(
            serverBase: _serverBase,
            port: order.port,
            addPort: order.addPort,
            client: _http,
            isCancelled: () => _paused || _stopping,
          ),
          record: () => _record,
          broker: _broker,
          expected: order.catalogServerId!,
        )) {
      _paused = true;
      _sendEvent({'kind': 'parked', 'reason': 'server identity not verified'});
    }
    await _drain();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    switch (data['op']) {
      case 'add':
        final id = data['chapterId'] as int;
        final generation = data['gen'] as int? ?? 0;
        if (generation < (_genOf[id] ?? 0)) break;
        if (id == _inFlight) break; // already downloading — don't double-queue
        // A newer-generation add supersedes prior cancellation and must stamp its own events.
        _cancelled.remove(id);
        _genOf[id] = generation;
        if (!_queue.contains(id) && !_mangaOf.containsKey(id)) {
          _queue.add(id);
          _mangaOf[id] = data['mangaId'] as int;
          _total++;
          _sawNewWork = true;
        } else if (!_queue.contains(id)) {
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
        _paused = true;
        _http.close();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopping = true;
    _yieldTimer?.cancel();
    _http.close();
    if (_ownsLock) {
      try {
        try {
          await _drainFuture;
        } catch (_) {}
        await _controlCheck;
        if (isTimeout && _ownsLock) await _log.appendTimeout();
      } finally {
        await _releaseOwnership();
      }
    }
    if (isTimeout) {
      _sendEvent({'kind': 'timedOut', 'at': timestamp.toIso8601String()});
    }
  }

  Future<bool> _controlsAllow(BackgroundWorkOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final controls = CatchupStateStore(prefs);
    if (controls.paused ||
        (order.catalogServerId != null &&
            controls.downloadPermissionPaused(order.catalogServerId!)) ||
        !controls.identityAuthorized ||
        controls.identityEpoch != order.identityEpoch ||
        order.catalogServerId == null ||
        controls.catalogServerId != order.catalogServerId ||
        prefs.getString(offlineLastServerIdKey(prefs)) !=
            order.catalogServerId ||
        prefs.getString(offlineLastServerAddressKey(prefs)) !=
            serverAddress(
              baseUrl: order.serverBase,
              port: order.port,
              addPort: order.addPort,
            )) {
      return false;
    }
    _wifiOnly =
        prefs.getBool(DBKeys.downloadOnlyOverWifi.name) ?? order.wifiOnly;
    final network = await Connectivity().checkConnectivity();
    return !network.contains(ConnectivityResult.none) &&
        (!_wifiOnly ||
            network.contains(ConnectivityResult.wifi) ||
            network.contains(ConnectivityResult.ethernet));
  }

  Future<void> _checkControls() async {
    if (_paused || _stopping) return;
    try {
      if (await _lock!.yieldRequested()) {
        _paused = true;
      } else {
        final now = DateTime.now();
        if (_lastControlRefresh == null ||
            now.difference(_lastControlRefresh!) >=
                const Duration(seconds: 2)) {
          _lastControlRefresh = now;
          if (!await _controlsAllow(_order!)) _paused = true;
        }
      }
      if (_paused) _http.close();
    } catch (_) {
      _paused = true;
      _http.close();
    }
  }

  Future<void> _releaseOwnership() async {
    _ownsLock = false;
    await _lock?.release();
  }


  Future<void> _drain() async {
    while (!_stopping && !_paused) {
      final next = _queue.where((c) => !_cancelled.contains(c)).firstOrNull;
      if (next == null) {
        if (_sawNewWork) {
          _sawNewWork = false;
          continue;
        }
        // Record drain before self-stop so main can pick up work queued during shutdown.
        await _log.appendDrained();
        if (_stopping) return;
        _sendEvent({'kind': 'drained'});
        await _releaseOwnership();
        await FlutterForegroundTask.stopService();
        return;
      }
      _queue.remove(next);
      _inFlight = next;
      final parked = await _downloadChapter(next, _mangaOf[next]!);
      _inFlight = null;
      if (_stopping) return;
      if (parked) {
        // Park without a drained marker; drift retains the queue for reconnect.
        await _releaseOwnership();
        await FlutterForegroundTask.stopService();
        return;
      }
    }
    // Pause preserves drift work and must not emit a drained marker.
    if (_paused && !_stopping) {
      await _releaseOwnership();
      await FlutterForegroundTask.stopService();
    }
  }

  /// True means park the drain with resumable work intact.
  Future<bool> _downloadChapter(
    int chapterId,
    int mangaId, {
    bool afterRepick = false,
  }) async {
    List<String>? urls;
    String? errorMessage;
    try {
      urls = await _resolvePageUrls(chapterId);
    } on OperationMessageException catch (error) {
      if (_paused || _stopping || _cancelled.contains(chapterId)) return false;
      errorMessage = error.toString();
      urls = const [];
    } on AccountPermissionDenied {
      await _recordPermissionDenied(chapterId);
      return true;
    }
    if (_paused || _stopping || _cancelled.contains(chapterId)) return false;
    if (urls == null) {
      if (!afterRepick && await _repickServer()) {
        return _downloadChapter(chapterId, mangaId, afterRepick: true);
      }
      // Notify main to arm backoff before the stop handshake sees pending drift work.
      _sendEvent({
        'kind': 'parked',
        'chapterId': chapterId,
        'mangaId': mangaId,
        'reason': _lastNetworkErrorReason,
      });
      return true;
    }
    if (urls.isEmpty) {
      await _log.appendChapter(
        chapterId: chapterId,
        status: 'error',
        reason: errorMessage,
        pages: 0,
        bytes: 0,
        generation: _genOf[chapterId] ?? 0,
      );
      _done++;
      _afterChapter(chapterId, 'error', offlineReason: errorMessage);
      return false;
    }

    _sendEvent({
      'kind': 'chapterStart',
      'chapterId': chapterId,
      'gen': _genOf[chapterId] ?? 0,
      // Webtoon page totals are unknown until the worker resolves the page list.
      'total': urls.length,
    });

    final generation = _genOf[chapterId] ?? 0;
    final indices = [for (var i = 0; i < urls.length; i++) i];
    final staged = await _openStaging(mangaId, chapterId, indices, generation);

    final engine = _buildEngine();
    final pages = [
      for (var i = 0; i < urls.length; i++)
        if (!staged.contains(i)) (index: i, url: urls[i]),
    ];
    var done = staged.length;
    final outcome = await engine.download(
      mangaId: mangaId,
      chapterId: chapterId,
      pages: pages,
      isCancelled: () => _cancelled.contains(chapterId) || _stopping || _paused,
      onPageStored: (i, rel, bytes) async {
        // The main isolate publishes staging; worker page events report progress only.
        _sendEvent({
          'kind': 'page',
          'chapterId': chapterId,
          'gen': generation,
          'done': ++done,
          'total': urls!.length,
        });
      },
    );

    if (outcome.error is AccountPermissionDenied && !outcome.cancelled) {
      await _recordPermissionDenied(chapterId);
      return true;
    }
    final String? status = outcome.cancelled || _paused || _stopping
        ? null
        : outcome.succeeded
        ? 'downloaded'
        : outcome.offline
        ? 'offline'
        : outcome.authFailed
        ? 'authFailed'
        : 'error';

    if (status != null) {
      // The committer measures final bytes after promotion.
      await _log.appendChapter(
        chapterId: chapterId,
        status: status,
        pages: urls.length,
        bytes: 0,
        generation: generation,
      );
      _done++;
    }
    _afterChapter(chapterId, status, offlineReason: outcome.offlineReason);
    return status == 'offline' || status == 'authFailed';
  }

  // Resume only staging with matching pages and generation.
  Future<Set<int>> _openStaging(
    int mangaId,
    int chapterId,
    List<int> indices,
    int generation,
  ) async {
    final existing = await _store.readManifest(mangaId, chapterId);
    if (existing != null &&
        existing.generation == generation &&
        existing.coversSameIndices(indices)) {
      return _store.stagedPageIndices(mangaId, chapterId);
    }
    await _store.deleteStaging(mangaId, chapterId);
    await _store.beginChapter(
      mangaId,
      chapterId,
      ChapterManifest(generation: generation, indices: indices),
    );
    return const {};
  }

  void _afterChapter(int chapterId, String? status, {String? offlineReason}) {
    _sendEvent({
      'kind': 'chapterDone',
      'chapterId': chapterId,
      'mangaId': _mangaOf[chapterId],
      'gen': _genOf[chapterId] ?? 0,
      'status': status,
      'reason': offlineReason,
    });
    // The plugin replaces notification content wholesale; include the icon on every update.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Downloading chapters',
      notificationText: 'Downloading — $_done/$_total',
      notificationIcon: const NotificationIcon(
        metaDataName: kNotificationIconMetaData,
      ),
    );
  }


  Future<void> _recordPermissionDenied(int chapterId) async {
    final order = _order!;
    final catalogId = order.catalogServerId;
    if (catalogId == null ||
        _paused ||
        _stopping ||
        _cancelled.contains(chapterId)) {
      return;
    }
    final controls = await CatchupStateStore.open();
    bool current() =>
        !_stopping &&
        !_cancelled.contains(chapterId) &&
        controls.identityAuthorized &&
        controls.identityEpoch == order.identityEpoch &&
        controls.catalogServerId == catalogId;
    final saved = await controls.recordDownloadPermission(
      catalogId,
      allowed: false,
      expectedRevision: controls.downloadPermissionRevision(catalogId),
      isCurrent: current,
      baseDir: _paths.baseDir,
    );
    if (!saved || !current()) return;
    await _log.appendChapter(
      chapterId: chapterId,
      status: 'permissionDenied',
      pages: 0,
      bytes: 0,
      generation: _genOf[chapterId] ?? 0,
    );
    if (current()) {
      _sendEvent({
        'kind': 'chapterDone',
        'chapterId': chapterId,
        'mangaId': order.mangaIdByChapter[chapterId],
        'status': 'permissionDenied',
        'gen': _genOf[chapterId] ?? 0,
      });
    }
    _paused = true;
  }

  String? _lastNetworkErrorReason;

  Future<bool> _repickServer() async {
    final order = _order;
    if (order == null || _paused || _stopping) return false;
    final next = await pickBackgroundServerBase(
      active: order.serverBase,
      lanUrl: order.lanUrl,
      externalUrl: order.externalUrl,
      source: 'download-retry',
    );
    if (next == _serverBase) return false;
    return switchServerBaseIfVerified(
      base: () => _serverBase,
      setBase: (base) => _serverBase = base,
      next: next,
      verify: () => verifyBackgroundServerIdentity(
        target: BackgroundServerTarget(
          serverBase: next,
          port: order.port,
          addPort: order.addPort,
          client: _http,
          isCancelled: () => _paused || _stopping,
        ),
        record: () => _record,
        broker: _broker,
        expected: order.catalogServerId!,
      ),
    );
  }

  // Null parks for retry; an empty list is a terminal no-pages result.
  Future<List<String>?> _resolvePageUrls(int chapterId) =>
      resolveChapterPageUrls(
        target: BackgroundServerTarget(
          serverBase: _serverBase,
          port: _order!.port,
          addPort: _order!.addPort,
          client: _http,
          onNetworkError: (reason) => _lastNetworkErrorReason = reason,
          isCancelled: () =>
              _paused || _stopping || _cancelled.contains(chapterId),
        ),
        record: () => _record,
        broker: _broker,
        chapterId: chapterId,
      );

  ChapterDownloadEngine _buildEngine() => ChapterDownloadEngine(
    writePage: _store,
    parallelPageLimit: 5,
    fetchPage: (pageUrl) async {
      await _broker.refreshIfDue(_record);
      final (url, headers) = _authedPageRequest(pageUrl);
      final http.Response res;
      try {
        res = await _http
            .get(Uri.parse(url), headers: headers)
            .timeout(_httpTimeout);
      } on http.ClientException catch (e) {
        throw PageOfflineException('ClientException: $e');
      } on SocketException catch (e) {
        throw PageOfflineException('SocketException: $e');
      } on TimeoutException {
        throw PageOfflineException(
          'timed out after $_httpTimeout on page fetch',
        );
      }
      if (res.statusCode == 401) throw const PageAuthException();
      if (res.statusCode == 403) {
        throw const AccountPermissionDenied(
          Enum$UserPermission.DOWNLOAD_CHAPTERS,
        );
      }
      // Gateway failures leave work resumable rather than consuming chapter retries.
      if (isGatewayStatus(res.statusCode)) {
        throw PageOfflineException('HTTP ${res.statusCode} on page fetch');
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
      if (_record.authType != 'uiLogin') return false;
      final newAccess = await _broker.resolveAfter401(
        _record.accessToken ?? '',
      );
      return newAccess != null;
    },
  );

  // Page URLs already include /api; use current broker auth and the server base without /api.
  (String, Map<String, String>) _authedPageRequest(String pageUrl) {
    final order = _order!;
    final base = Endpoints.baseApi(
      baseUrl: _serverBase,
      port: order.port,
      addPort: order.addPort,
      appendApiToUrl: false,
    );
    final fetchUrl = '$base$pageUrl';
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
          headers['Authorization'] = 'Bearer $token';
        }
    }
    applyIsolateCustomHeaders(headers, _record.extraHeaders);
    return (fetchUrl, headers);
  }


  TokenBroker _buildBroker() => TokenBroker(
    expectedIdentity: _order!.auth,
    read: () async {
      final raw = await FlutterForegroundTask.getData<String>(
        key: kTokenRecordKey,
      );
      if (raw == null) return _record;
      final current = BackgroundTokenRecord.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
      if (current.sameIdentity(_order!.auth)) _record = current;
      return current;
    },
    write: (r) => withWorkOrderAdmission(_paths.baseDir, () async {
      final order = decodeWorkOrder(
        await FlutterForegroundTask.getData<String>(key: kWorkOrderKey),
      );
      if (_stopping || !_ownsLock || order?.attemptId != _order?.attemptId) {
        return;
      }
      _record = r;
      if (!await FlutterForegroundTask.saveData(
        key: kTokenRecordKey,
        value: jsonEncode(r.toJson()),
      )) {
        throw StateError('Failed to save refreshed download credentials');
      }
    }),
    refreshFn: (refreshToken) async {
      if (_record.authType != 'uiLogin') {
        return (tokens: null, transient: false);
      }
      final order = _order!;
      final endpoint = Endpoints.baseApi(
        baseUrl: _serverBase,
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
        final res = await _http
            .post(
              Uri.parse(endpoint),
              headers: applyIsolateCustomHeaders({
                'Content-Type': 'application/json',
              }, _record.extraHeaders),
              body: body,
            )
            .timeout(_httpTimeout);
        // A gateway failure means unreachable origin, not invalid refresh credentials.
        if (isGatewayStatus(res.statusCode)) {
          logBackgroundRefresh(
            'download',
            'gateway status=${res.statusCode} transient=true',
          );
          return (tokens: null, transient: true);
        }
        if (res.statusCode != 200) {
          logBackgroundRefresh(
            'download',
            'rejected status=${res.statusCode} transient=false',
          );
          return (tokens: null, transient: false);
        }
        final decoded = jsonDecode(res.body) as Map<String, Object?>;
        final data = decoded['data'] as Map<String, Object?>?;
        final refreshed = data?['refreshToken'] as Map<String, Object?>?;
        final access = refreshed?['accessToken'] as String?;
        if (access == null || access.isEmpty) {
          logBackgroundRefresh(
            'download',
            'no-token transient=false errors=${decoded['errors']}',
          );
          return (tokens: null, transient: false);
        }
        // Suwayomi does not rotate refresh tokens; retain the input token.
        return (
          tokens: (access: access, refresh: refreshToken),
          transient: false,
        );
      } on SocketException catch (e) {
        logBackgroundRefresh('download', 'network-error transient=true', e);
        return (tokens: null, transient: true);
      } on TimeoutException catch (e) {
        logBackgroundRefresh('download', 'timeout transient=true', e);
        return (tokens: null, transient: true);
      } catch (e) {
        logBackgroundRefresh('download', 'error transient=false', e);
        return (tokens: null, transient: false);
      }
    },
  );
}
