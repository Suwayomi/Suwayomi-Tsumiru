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

  test('append + parse round-trips chapter, deleted, drained', () async {
    final log = BackgroundCompletionLog(logFile);
    await log.appendChapter(chapterId: 5, status: 'error', pages: 2, bytes: 0);
    await log.appendDeleted(7, 3);
    await log.appendDrained();

    final entries = await log.parse();
    expect(entries.length, 3);
    expect((entries[0] as ChapterEntry).status, 'error');
    expect((entries[1] as DeletedEntry).generation, 3);
    expect(entries[2], isA<DrainedEntry>());
  });

  test('per-page lines from an older build are ignored, not parsed', () async {
    // Page lines were dropped when chapters became atomic; a log left by the
    // previous build must still parse, minus them.
    final log = BackgroundCompletionLog(logFile);
    await logFile.writeAsString(
      '{"t":"page","c":5,"m":1,"i":0,"p":"1/5/000.jpg","b":10,"g":0}\n',
      mode: FileMode.append,
    );
    await log.appendDrained();

    final entries = await log.parse();
    expect(entries.single, isA<DrainedEntry>());
  });

  test(
    'a torn final line (crash mid-write) is discarded, earlier lines kept',
    () async {
      final log = BackgroundCompletionLog(logFile);
      await log.appendChapter(
        chapterId: 5,
        status: 'error',
        pages: 1,
        bytes: 0,
      );
      // simulate a partial trailing write (no newline, invalid json)
      await logFile.writeAsString(
        '{"t":"chapter","c":5,"s":"err',
        mode: FileMode.append,
      );
      final entries = await log.parse();
      expect(entries.length, 1);
      expect((entries.single as ChapterEntry).chapterId, 5);
    },
  );

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
