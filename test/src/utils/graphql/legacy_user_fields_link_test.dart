import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/offline/data/background/background_chapter_fetch.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/utils/graphql/legacy_user_fields_link.dart';
import 'package:tsumiru/src/utils/logger/logger_link.dart';

Request request(String source, {Map<String, dynamic> variables = const {}}) =>
    Request(
      operation: Operation(document: parseString(source)),
      variables: variables,
    );

bool isProbe(Request request) => printNode(
  request.operation.document,
).contains('__type(name: "ChapterType")');

Response capability(bool modern) => Response(
  data: {
    '__type': {
      'fields': [
        {'name': 'id'},
        if (modern) {'name': 'user'},
      ],
    },
  },
  response: const {},
);

Future<Response> legacy(
  Request original,
  Map<String, dynamic> data, {
  void Function(Request)? inspect,
}) => LegacyUserFieldsLink().request(original, (outgoing) async* {
  if (isProbe(outgoing)) {
    yield capability(false);
  } else {
    inspect?.call(outgoing);
    yield Response(data: data, response: const {});
  }
}).first;

void main() {
  for (final modern in [false, true]) {
    test(
      modern
          ? 'modern subscriptions pass through after an HTTP probe'
          : 'legacy subscriptions use HTTP detection and reshape socket events',
      () async {
        final original = request(
          r'''
          subscription DownloadStatusChanged($input: DownloadChangedInput!) {
            downloadStatusChanged(input: $input) { ...DownloadUpdatesDto }
          }
          fragment DownloadUpdatesDto on DownloadUpdates {
            state omittedUpdates
            initial { ...DownloadDto }
            updates { type download { ...DownloadDto } }
          }
          fragment DownloadDto on DownloadType {
            chapter { id user { isDownloaded } }
            manga { id user { downloadCount } }
            progress state
          }
        ''',
          variables: {'input': <String, dynamic>{}},
        );
        Map<String, dynamic> event(bool downloaded, {required bool nested}) {
          final download = {
            'chapter': {
              'id': 1,
              if (nested)
                'user': {'isDownloaded': downloaded}
              else
                'isDownloaded': downloaded,
            },
            'manga': {
              'id': 2,
              if (nested)
                'user': {'downloadCount': downloaded ? 1 : 0}
              else
                'downloadCount': downloaded ? 1 : 0,
            },
            'progress': downloaded ? 1.0 : 0.5,
            'state': downloaded ? 'FINISHED' : 'DOWNLOADING',
          };
          return {
            'downloadStatusChanged': {
              'state': 'STARTED',
              'omittedUpdates': false,
              'initial': [download],
              'updates': [
                {'type': 'CHANGED', 'download': download},
              ],
            },
          };
        }

        final detection = LegacyUserFieldsDetection();
        var probes = 0;
        final httpTransport = MockClient((incoming) async {
          expect(incoming.headers['authorization'], 'Bearer test-token');
          final body = jsonDecode(incoming.body) as Map;
          final source = body['query'] as String;
          if (source.contains('__type(')) probes++;
          return http.Response(
            jsonEncode({
              'data': source.contains('__type(')
                  ? capability(modern).data
                  : {'chapter': null},
            }),
            200,
          );
        });
        addTearDown(httpTransport.close);
        final httpChain = LoggerLink()
            .concat(LegacyUserFieldsLink(detection: detection))
            .concat(AuthLink(getToken: () => 'Bearer test-token'))
            .concat(
              HttpLink('http://probe.test/graphql', httpClient: httpTransport),
            );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var socketQueries = 0;
        var subscriptions = 0;
        server.transform(WebSocketTransformer()).listen((socket) {
          socket.listen((raw) {
            final frame = jsonDecode(raw as String) as Map;
            if (frame['type'] == 'connection_init') {
              socket.add(jsonEncode({'type': 'connection_ack'}));
            } else if (frame['type'] == 'subscribe') {
              final payload = frame['payload'] as Map;
              final source = payload['query'] as String;
              if (source.contains('__type(')) {
                socketQueries++;
                socket.add(jsonEncode({'type': 'error', 'id': frame['id']}));
                return;
              }
              subscriptions++;
              expect(source.contains('user {'), modern);
              if (modern) {
                expect(source, printNode(original.operation.document));
              }
              expect(payload['variables'], original.variables);
              for (final downloaded in [false, true]) {
                socket.add(
                  jsonEncode({
                    'type': 'next',
                    'id': frame['id'],
                    'payload': {'data': event(downloaded, nested: modern)},
                  }),
                );
              }
              socket.add(jsonEncode({'type': 'complete', 'id': frame['id']}));
            }
          });
        });
        final socketLink = WebSocketLink(
          'ws://127.0.0.1:${server.port}',
          subProtocol: GraphQLProtocol.graphqlTransportWs,
          config: const SocketClientConfig(autoReconnect: false),
        );
        addTearDown(socketLink.dispose);
        final subscriptionChain = LoggerLink()
            .concat(
              LegacyUserFieldsLink(
                detection: detection,
                probe: (request) => httpChain.request(request),
              ),
            )
            .concat(socketLink);
        for (var attempt = 0; attempt < 2; attempt++) {
          final responses = await subscriptionChain
              .request(original)
              .take(2)
              .toList();
          expect(responses.map((response) => response.data).toList(), [
            event(false, nested: true),
            event(true, nested: true),
          ]);
        }
        await httpChain
            .request(request('{ chapter { user { isRead } } }'))
            .first;
        expect(probes, 1);
        expect(socketQueries, 0);
        expect(subscriptions, 2);
      },
    );
  }

  group('background POST', () {
    const query = '{ chapter { user { isRead } } }';
    const record = BackgroundTokenRecord(
      gen: 0,
      authType: 'uiLogin',
      accessToken: 'stored',
    );

    Future<Object?> post(String host, http.Client client) =>
        postBackgroundGraphql(
          target: BackgroundServerTarget(
            serverBase: 'https://$host.test',
            port: null,
            addPort: false,
            client: client,
          ),
          record: record,
          accessToken: 'override',
          query: query,
          variables: const {},
        );

    for (final modern in [false, true]) {
      test(
        modern ? 'modern pass-through' : 'legacy rewrite and reshape',
        () async {
          var probes = 0;
          var requests = 0;
          final client = MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer override');
            final body = jsonDecode(request.body) as Map;
            final source = body['query'] as String;
            if (source.contains('__type(')) {
              probes++;
              expect(body['variables'], isEmpty);
              return http.Response(
                jsonEncode({'data': capability(modern).data}),
                200,
              );
            }
            requests++;
            if (modern) {
              expect(source, query);
            } else {
              expect(source, isNot(contains('user {')));
              expect(source, contains('isRead'));
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'chapter': modern
                      ? {
                          'user': {'isRead': true},
                        }
                      : {'isRead': true},
                },
              }),
              200,
            );
          });
          for (var i = 0; i < 2; i++) {
            expect(await post('background-$modern', client), {
              'chapter': {
                'user': {'isRead': true},
              },
            });
          }
          expect(probes, 1);
          expect(requests, 2);
        },
      );
    }

    test('cache is per endpoint and concurrent calls share a probe', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final probes = <String, int>{};
      final client = MockClient((request) async {
        final source = (jsonDecode(request.body) as Map)['query'] as String;
        if (source.contains('__type(')) {
          probes.update(
            request.url.host,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          if (!started.isCompleted) started.complete();
          await gate.future;
          return http.Response(
            jsonEncode({
              'data': capability(request.url.host.contains('modern')).data,
            }),
            200,
          );
        }
        expect(source.contains('user {'), request.url.host.contains('modern'));
        return http.Response(
          jsonEncode({
            'data': {'chapter': null},
          }),
          200,
        );
      });
      final first = post('cache-legacy', client);
      await started.future;
      final second = post('cache-legacy', client);
      gate.complete();
      await Future.wait([first, second]);
      await post('cache-legacy', client);
      await post('cache-modern', client);
      await post('cache-modern', client);
      expect(probes, {'cache-legacy.test': 1, 'cache-modern.test': 1});
    });

    test(
      'auth sentinel from probe is not cached and forwards unchanged',
      () async {
        var probes = 0;
        var requests = 0;
        final client = MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer override');
          final source = (jsonDecode(request.body) as Map)['query'] as String;
          if (source.contains('__type(')) {
            probes++;
            if (probes == 1) return http.Response('', 401);
            return http.Response(
              jsonEncode({'data': capability(false).data}),
              200,
            );
          }
          requests++;
          if (requests == 1) {
            expect(source, query);
            return http.Response('', 401);
          }
          expect(source, isNot(contains('user {')));
          return http.Response(
            jsonEncode({
              'data': {
                'chapter': {'isRead': false},
              },
            }),
            200,
          );
        });
        expect(await post('retry-auth', client), same(gqlAuthError));
        for (var i = 0; i < 2; i++) {
          expect(await post('retry-auth', client), {
            'chapter': {
              'user': {'isRead': false},
            },
          });
        }
        expect(probes, 2);
        expect(requests, 3);
      },
    );
  });

  test(
    'modern server forwards the identical request and caches the probe',
    () async {
      final link = LegacyUserFieldsLink();
      final original = request('{ chapter { user { isRead } } }');
      var probes = 0;
      final response = Response(
        data: const {'chapter': null},
        response: const {},
      );
      Stream<Response> forward(Request outgoing) async* {
        if (isProbe(outgoing)) {
          probes++;
          yield capability(true);
        } else {
          expect(identical(outgoing, original), isTrue);
          expect(
            identical(outgoing.operation.document, original.operation.document),
            isTrue,
          );
          yield response;
        }
      }

      expect(
        identical(await link.request(original, forward).first, response),
        isTrue,
      );
      await link.request(original, forward).first;
      expect(probes, 1);
    },
  );

  test(
    'ChapterDto fragments hoist fields and restore lists and nulls',
    () async {
      final original = request('''
      query Chapters { chapters { nodes { ...ChapterDto } } }
      fragment ChapterDto on ChapterType {
        __typename id
        user { __typename chapterId isRead isBookmarked isDownloaded lastPageRead lastReadAt }
      }
    ''');
      final result = await legacy(
        original,
        {
          'chapters': {
            'nodes': [
              {
                '__typename': 'ChapterType',
                'id': 1,
                'chapterId': 1,
                'isRead': true,
                'isBookmarked': false,
                'isDownloaded': true,
                'lastPageRead': 4,
                'lastReadAt': null,
              },
              null,
            ],
          },
        },
        inspect: (outgoing) {
          final source = printNode(outgoing.operation.document);
          expect(source, isNot(contains('user {')));
          expect(source, contains('chapterId: id'));
          expect(source, contains('fragment ChapterDto on ChapterType'));
        },
      );
      expect(result.data, {
        'chapters': {
          'nodes': [
            {
              '__typename': 'ChapterType',
              'id': 1,
              'user': {
                '__typename': 'ChapterUserType',
                'chapterId': 1,
                'isRead': true,
                'isBookmarked': false,
                'isDownloaded': true,
                'lastPageRead': 4,
                'lastReadAt': null,
              },
            },
            null,
          ],
        },
      });
    },
  );

  test(
    'MangaDto restores nested chapter users and inline manga fields',
    () async {
      final result = await legacy(
        request('''
      query { chapter { manga { ...MangaDto user { inLibrary unreadCount } } } }
      fragment MangaDto on MangaType {
        id user {
          mangaId __typename inLibraryAt bookmarkCount downloadCount
          firstUnreadChapter { id }
          lastReadChapter { id user { __typename isRead } }
          latestReadChapter { id user { lastPageRead } }
        }
      }
    '''),
        {
          'chapter': {
            'manga': {
              '__typename': 'MangaType',
              'id': 2,
              'mangaId': 2,
              'inLibrary': true,
              'unreadCount': 3,
              'inLibraryAt': '123',
              'bookmarkCount': 1,
              'downloadCount': 2,
              'firstUnreadChapter': null,
              'lastReadChapter': {
                '__typename': 'ChapterType',
                'id': 8,
                'isRead': true,
              },
              'latestReadChapter': {'id': 9, 'lastPageRead': 2},
            },
          },
        },
        inspect: (outgoing) {
          expect(
            printNode(outgoing.operation.document),
            isNot(contains('user {')),
          );
        },
      );
      expect(result.data, {
        'chapter': {
          'manga': {
            'id': 2,
            'user': {
              'mangaId': 2,
              '__typename': 'MangaUserType',
              'inLibraryAt': '123',
              'bookmarkCount': 1,
              'downloadCount': 2,
              'firstUnreadChapter': null,
              'lastReadChapter': {
                'id': 8,
                'user': {'__typename': 'ChapterUserType', 'isRead': true},
              },
              'latestReadChapter': {
                'id': 9,
                'user': {'lastPageRead': 2},
              },
              'inLibrary': true,
              'unreadCount': 3,
            },
          },
        },
      });
    },
  );

  test(
    'aliases, child arguments and include directives survive hoisting',
    () async {
      final original = request(
        r'''
      query Test($withFirst: Boolean!) {
        manga {
          state: user {
            library: inLibrary
            first: firstUnreadChapter(offset: 1) @include(if: $withFirst) { id }
          }
        }
      }
    ''',
        variables: {'withFirst': true},
      );
      final result = await legacy(
        original,
        {
          'manga': {
            'library': true,
            'first': {'id': 7},
          },
        },
        inspect: (outgoing) {
          final source = printNode(outgoing.operation.document);
          expect(source, contains('library: inLibrary'));
          expect(
            source,
            contains(
              r'first: firstUnreadChapter(offset: 1) @include(if: $withFirst)',
            ),
          );
          expect(outgoing.variables, same(original.variables));
          expect(outgoing.context, same(original.context));
        },
      );
      expect(result.data, {
        'manga': {
          'state': {
            'library': true,
            'first': {'id': 7},
          },
        },
      });
    },
  );

  test('account user selections pass through untouched', () async {
    final original = request(
      '{ user { id username } manga { user { id username } } }',
    );
    final data = {
      'user': {'id': 1, 'username': 'reader'},
      'manga': null,
    };
    final result = await legacy(
      original,
      data,
      inspect: (outgoing) {
        expect(outgoing.operation.document, original.operation.document);
      },
    );
    expect(result.data, data);
  });

  test(
    'inline fragments and directly selected keys remain on the parent',
    () async {
      final result = await legacy(
        request('''
      { chapter { ... on ChapterType { isRead user { isRead lastPageRead } } } }
    '''),
        {
          'chapter': {'isRead': true, 'lastPageRead': 5},
        },
      );
      expect(result.data, {
        'chapter': {
          'isRead': true,
          'user': {'isRead': true, 'lastPageRead': 5},
        },
      });
    },
  );

  test(
    'subscription events without typename are reshaped independently',
    () async {
      final original = request('''
      subscription Updates { update { chapters { user { isRead } manga { user { inLibrary } } } } }
    ''');
      final responses = await LegacyUserFieldsLink().request(original, (
        outgoing,
      ) async* {
        if (isProbe(outgoing)) {
          yield capability(false);
        } else {
          for (final read in [true, false]) {
            yield Response(
              data: {
                'update': {
                  'chapters': [
                    {
                      'isRead': read,
                      'manga': {'inLibrary': true},
                    },
                    null,
                  ],
                },
              },
              response: const {},
            );
          }
        }
      }).toList();
      expect(responses.map((response) => response.data).toList(), [
        for (final read in [true, false])
          {
            'update': {
              'chapters': [
                {
                  'user': {'isRead': read},
                  'manga': {
                    'user': {'inLibrary': true},
                  },
                },
                null,
              ],
            },
          },
      ]);
    },
  );

  test('typename and ids infer the user type from the parent', () async {
    final result = await legacy(
      request('{ manga { user { __typename key: mangaId } } }'),
      {
        'manga': {'__typename': 'MangaType', 'key': 4},
      },
      inspect: (outgoing) {
        expect(printNode(outgoing.operation.document), contains('key: id'));
      },
    );
    expect(result.data, {
      'manga': {
        'user': {'__typename': 'MangaUserType', 'key': 4},
      },
    });
  });

  test(
    'mutation errors and response metadata pass through unchanged',
    () async {
      final errors = [const GraphQLError(message: 'partial failure')];
      final raw = <String, dynamic>{
        'extensions': {'trace': 1},
      };
      final context = Context();
      final result = await LegacyUserFieldsLink().request(
        request('mutation { updateChapter { user { isRead } } }'),
        (outgoing) async* {
          if (isProbe(outgoing)) {
            yield capability(false);
          } else {
            yield Response(
              data: {'updateChapter': null},
              errors: errors,
              response: raw,
              context: context,
            );
          }
        },
      ).first;
      expect(result.errors, same(errors));
      expect(result.response, same(raw));
      expect(result.context, same(context));
      expect(result.data, {'updateChapter': null});
    },
  );

  for (final failure in ['network', 'graphql', 'missing fields']) {
    test(
      '$failure probe failure forwards unchanged and retries next time',
      () async {
        final link = LegacyUserFieldsLink();
        final original = request('{ chapter { user { isRead } } }');
        var probes = 0;
        var requests = 0;
        Stream<Response> forward(Request outgoing) async* {
          if (isProbe(outgoing)) {
            probes++;
            if (probes > 1) {
              yield capability(false);
            } else if (failure == 'network') {
              throw StateError('offline');
            } else if (failure == 'graphql') {
              yield Response(
                data: capability(false).data,
                errors: [const GraphQLError(message: 'denied')],
                response: const {},
              );
            } else {
              yield const Response(data: {'__type': null}, response: {});
            }
          } else {
            requests++;
            if (requests == 1) {
              expect(outgoing, same(original));
            } else {
              expect(
                printNode(outgoing.operation.document),
                isNot(contains('user {')),
              );
            }
            yield const Response(data: {'chapter': null}, response: {});
          }
        }

        for (var i = 0; i < 3; i++) {
          await link.request(original, forward).first;
        }
        expect(probes, 2);
        expect(requests, 3);
      },
    );
  }

  test(
    'concurrent operations share an in-flight probe and cache success',
    () async {
      final link = LegacyUserFieldsLink();
      final gate = Completer<Response>();
      final started = Completer<void>();
      var probes = 0;
      Stream<Response> forward(Request outgoing) async* {
        if (isProbe(outgoing)) {
          probes++;
          if (!started.isCompleted) started.complete();
          yield await gate.future;
        } else {
          yield const Response(data: {'chapter': null}, response: {});
        }
      }

      final original = request('{ chapter { user { isRead } } }');
      final first = link.request(original, forward).first;
      final second = link.request(original, forward).first;
      await started.future;
      gate.complete(capability(false));
      await Future.wait([first, second]);
      await link.request(original, forward).first;
      expect(probes, 1);
    },
  );

  test('operation exceptions are not swallowed', () async {
    final error = StateError('operation failed');
    await expectLater(
      LegacyUserFieldsLink().request(
        request('{ chapter { user { isRead } } }'),
        (outgoing) async* {
          if (isProbe(outgoing)) {
            yield capability(false);
          } else {
            throw error;
          }
        },
      ).first,
      throwsA(same(error)),
    );
  });
}
