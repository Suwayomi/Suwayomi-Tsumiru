import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/background_work_order.dart';
import 'package:tsumiru/src/features/offline/data/background/download_task_handler.dart';
import 'package:tsumiru/src/features/offline/data/background/work_order_admission.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final generation in [0, 1]) {
    test(
      'preadmission add generation $generation merges saved work once',
      () async {
        final tmp = await Directory.systemTemp.createTemp('handler-admission-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var downloads = 0;
        var resolutions = 0;
        var stops = 0;
        var running = true;
        server.listen((request) async {
          if (request.method == 'GET') {
            downloads++;
            request.response.headers.contentType = ContentType('image', 'jpeg');
            request.response.add([1, 2, 3]);
          } else {
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            final query = body['query'] as String;
            Object data;
            if (query.contains('OfflineServerIdentity')) {
              data = {
                'metas': {
                  'nodes': [
                    {'value': 'catalog-uuid'},
                  ],
                },
              };
            } else {
              expect(query, contains('GetChapterPages'));
              resolutions++;
              data = {
                'fetchChapterPages': {
                  'pages': ['/page/1.jpg'],
                },
              };
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'data': data}));
          }
          await request.response.close();
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async {
            expect(call.method, 'check');
            return ['wifi'];
          },
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_foreground_task/methods'),
          (call) async {
            switch (call.method) {
              case 'isRunningService':
                return running;
              case 'stopService':
                running = false;
                stops++;
                return null;
              case 'updateService':
                return null;
              default:
                throw StateError('Unexpected foreground call ${call.method}');
            }
          },
        );
        final base = 'http://127.0.0.1:${server.port}';
        SharedPreferences.setMockInitialValues({
          'offlineCatalogServerId': 'catalog-uuid',
          'offlineLastServerId': 'catalog-uuid',
          'offlineLastServerAddress': serverAddress(
            baseUrl: base,
            port: null,
            addPort: false,
          ),
        });
        final order = BackgroundWorkOrder(
          chapterIds: [1],
          mangaIdByChapter: {1: 1},
          generationByChapter: {1: 0},
          serverBase: base,
          port: null,
          addPort: false,
          wifiOnly: false,
          auth: const BackgroundTokenRecord(gen: 0, authType: 'none'),
          baseDir: tmp.path,
          attemptId: 'attempt',
          catalogServerId: 'catalog-uuid',
        );
        expect(
          await FlutterForegroundTask.saveData(
            key: kWorkOrderKey,
            value: jsonEncode(order.toJson()),
          ),
          isTrue,
        );
        await HttpOverrides.runZoned(() async {
          final handler = DownloadTaskHandler();
          addTearDown(() => handler.onDestroy(DateTime.now(), false));
          handler.onReceiveData({
            'op': 'add',
            'chapterId': 1,
            'mangaId': 1,
            'gen': generation,
          });
          if (generation > 0) {
            handler.onReceiveData({
              'op': 'add',
              'chapterId': 1,
              'mangaId': 1,
              'gen': 0,
            });
          }
          await handler
              .onStart(DateTime.now(), TaskStarter.developer)
              .timeout(const Duration(seconds: 5));
        }, createHttpClient: _RealHttpOverrides().createHttpClient);
        expect(downloads, 1);
        expect(resolutions, 1);
        expect(stops, 1);
        expect(
          await FlutterForegroundTask.getData<String>(
            key: kAcceptedWorkOrderKey,
          ),
          'attempt',
        );
        final entries = await BackgroundCompletionLog(
          File('${tmp.path}/.bg_completion.log'),
        ).parse();
        final completions = entries.whereType<ChapterEntry>().toList();
        expect(completions.length, 1);
        expect(completions.single.status, 'downloaded');
        expect(completions.single.generation, generation);
        expect(entries.whereType<DrainedEntry>().length, 1);
        final manifest = await IoOfflinePageStore(
          OfflinePaths(tmp.path),
        ).readManifest(1, 1);
        expect(manifest!.generation, generation);
      },
    );
  }
}
