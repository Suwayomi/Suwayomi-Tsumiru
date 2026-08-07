// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Breadcrumbs for non-fatal faults, written into the same log the crash
/// handlers use so Settings' copy action picks them up.
///
/// A sink rather than a direct write: the log path resolves once at startup and
/// callers deep in the widget tree can't await it. Tests swap it to capture.
typedef DiagnosticSink = void Function(String line);

DiagnosticSink? _sink;

void setDiagnosticSink(DiagnosticSink? sink) => _sink = sink;

void recordDiagnostic(String line) => _sink?.call(line);
