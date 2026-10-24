// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Use ref.read for gesture-time flags; watching them would trigger reader rebuilds.

import 'package:hooks_riverpod/legacy.dart';

/// Snapshot fling state on pointer-down: the first tap arrests it without opening chrome.
final readerTapArrestsFlingProvider = StateProvider<bool>((ref) => false);

/// Read zoom state during gestures so chapter-swipe recognizers yield to page panning.
final readerIsZoomedInProvider = StateProvider<bool>((ref) => false);
