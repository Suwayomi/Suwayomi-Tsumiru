import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_completion_log.dart';

void main() {
  late Directory tmp;
  late File logFile;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bglog');
    logFile = File('${tmp.path}/.bg_completion.log');
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('append + parse round-trips pages, chapter, drained', () async {
    final log = BackgroundCompletionLog(logFile);
    await log.appendPage(chapterId: 5, mangaId: 1, pageIndex: 0, relPath: '1/5/000.jpg', bytes: 1234);
    await log.appendPage(chapterId: 5, mangaId: 1, pageIndex: 1, relPath: '1/5/001.jpg', bytes: 2345);
    await log.appendChapter(chapterId: 5, status: 'downloaded', pages: 2, bytes: 3579);
    await log.appendDrained();

    final entries = await log.parse();
    expect(entries.length, 4);
    expect(entries[0], isA<PageEntry>());
    expect((entries[0] as PageEntry).relPath, '1/5/000.jpg');
    expect((entries[2] as ChapterEntry).status, 'downloaded');
    expect(entries[3], isA<DrainedEntry>());
  });

  test('a torn final line (crash mid-write) is discarded, earlier lines kept',
      () async {
    final log = BackgroundCompletionLog(logFile);
    await log.appendPage(chapterId: 5, mangaId: 1, pageIndex: 0, relPath: '1/5/000.jpg', bytes: 1234);
    // simulate a partial trailing write (no newline, invalid json)
    await logFile.writeAsString('{"t":"page","c":5,"m":1,"i":1,"p":"1/5/0',
        mode: FileMode.append);
    final entries = await log.parse();
    expect(entries.length, 1);
    expect((entries.single as PageEntry).pageIndex, 0);
  });

  test('parse on a missing file returns empty', () async {
    final log = BackgroundCompletionLog(logFile);
    expect(await log.parse(), isEmpty);
  });

  test('truncate empties the log', () async {
    final log = BackgroundCompletionLog(logFile);
    await log.appendDrained();
    await log.truncate();
    expect(await log.parse(), isEmpty);
  });
}
