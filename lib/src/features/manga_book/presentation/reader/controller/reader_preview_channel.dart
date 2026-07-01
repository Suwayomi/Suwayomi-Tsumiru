// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

// Ephemeral preview channels (design §2.4): slider onChanged writes ONLY these
// so the filter overlays repaint without a riverpod write — no tab or viewer
// rebuild mid-drag. null = no draft; overlays fall back to the committed pref.
// onChangeEnd (or sheet dismiss) commits to the provider and clears the draft.

/// Custom-brightness draft, -75..100.
final ValueNotifier<int?> readerBrightnessPreview = ValueNotifier(null);

/// Custom color-filter draft, packed ARGB.
final ValueNotifier<int?> readerColorFilterPreview = ValueNotifier(null);
