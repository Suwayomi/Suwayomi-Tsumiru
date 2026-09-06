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
    // debugPrint alone requires a live debugger attached to see it — anything
    // that happens in a background isolate (WorkManager, the foreground
    // download service) or on a release/profile build the user actually runs
    // was otherwise undiagnosable after the fact. Persisting warnings and
    // worse to the same crash-log file the Settings "copy crash log" action
    // reads makes every existing logger.w/.e call site in the app retroactively
    // visible there, not just the ones that happen to also call
    // recordDiagnostic directly.
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
