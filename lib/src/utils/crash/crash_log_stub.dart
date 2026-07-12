// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Web no-op: there's no filesystem to write a crash log to.
Future<String?> initCrashLog() async => null;

void writeCrashLog(String? path, String content) {}

String? readCrashLog(String? path) => null;

void clearCrashLog(String? path) {}
