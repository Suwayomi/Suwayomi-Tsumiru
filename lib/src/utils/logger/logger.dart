import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as l;
import 'package:logger/web.dart';

import '../crash/diagnostics.dart';

class Logger {
  static final l.Logger _logger = l.Logger(
    printer: l.PrettyPrinter(
      errorMethodCount: 30,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: MyConsoleOutput(),
  );

  const Logger._();

  static l.Logger get instance => _logger;
}

l.Logger get logger => Logger.instance;

class MyConsoleOutput extends ConsoleOutput {
  @override
  void output(OutputEvent event) {
    for (int i = 0; i < event.lines.length; i++) {
      debugPrint(event.lines[i]);
    }
    // Persist warnings/errors so background and release failures appear in the copied crash log.
    if (event.level == l.Level.warning ||
        event.level == l.Level.error ||
        event.level == l.Level.fatal) {
      final ts = DateTime.now().toIso8601String();
      for (final line in event.lines) {
        recordDiagnostic('[$ts] $line\n');
      }
    }
  }
}
