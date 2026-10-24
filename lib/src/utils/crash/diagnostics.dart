// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Shared crash-log sink; callers cannot await the log path resolved at startup.
typedef DiagnosticSink = void Function(String line);

DiagnosticSink? _sink;

void setDiagnosticSink(DiagnosticSink? sink) => _sink = sink;

void recordDiagnostic(String line) => _sink?.call(line);
