import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/offline/data/background/background_chapter_fetch.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../helpers/fake_page_store.dart';

void main() {
  const record = BackgroundTokenRecord(
    gen: 0,
    authType: 'uiLogin',
    accessToken: 'token',
  );
  var refreshes = 0;
  TokenBroker broker() => TokenBroker(
    read: () async => record,
    write: (_) async {},
    refreshFn: (_) async {
      refreshes++;
      return (tokens: null, transient: false);
    },
  );
  BackgroundServerTarget target(
    http.Client client, {
    bool Function()? cancelled,
  }) => BackgroundServerTarget(
    serverBase: 'http://server',
    port: null,
    addPort: false,
    client: client,
    isCancelled: cancelled,
  );
  setUp(() => refreshes = 0);

  test('a dead connection parks without retries or refresh, and a '
      'permission error bypasses retries too', () async {
    var requests = 0;
    final engine = buildBackgroundEngine(
      store: FakePageStore(),
      target: target(
        MockClient((_) async {
          requests++;
          throw http.ClientException('Connection closed');
        }),
      ),
      record: () => record,
      broker: broker(),
    );
    final outcome = await engine.download(
      mangaId: 1,
      chapterId: 2,
      pages: [(index: 0, url: '/page')],
      isCancelled: () => false,
    );
    expect(outcome.offline, isTrue);
    expect(requests, 1);
    expect(refreshes, 0);

    var fetches = 0;
    var backoffs = 0;
    final permissionEngine = ChapterDownloadEngine(
      writePage: FakePageStore(),
      fetchPage: (_) async {
        fetches++;
        throw const AccountPermissionDenied(
          Enum$UserPermission.DOWNLOAD_CHAPTERS,
        );
      },
      refreshAuth: () async {
        refreshes++;
        return true;
      },
      backoff: (_) {
        backoffs++;
        return Duration.zero;
      },
    );
    final result = await permissionEngine.download(
      mangaId: 1,
      chapterId: 2,
      pages: [(index: 0, url: '/page')],
      isCancelled: () => false,
    );
    expect(result.error, isA<AccountPermissionDenied>());
    expect(fetches, 1);
    expect(backoffs, 0);
    expect(refreshes, 0);
  });
}
