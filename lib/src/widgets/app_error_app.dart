// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/crash/copy_crash_log.dart';
import '../utils/motion/reduce_motion.dart';

/// Self-contained startup fallback; must render before app dependencies are ready.
class AppErrorApp extends StatelessWidget {
  const AppErrorApp({super.key, required this.message, this.logPath});

  final String message;
  final String? logPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) => Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      "Tsumiru couldn't start",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        final log = crashLogForClipboard(logPath) ?? message;
                        await Clipboard.setData(ClipboardData(text: log));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Log copied to clipboard'),
                            ),
                            snackBarAnimationStyle: context.snackBarMotionStyle,
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy log'),
                    ),
                    if (logPath != null) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        'Saved to:\n$logPath',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
