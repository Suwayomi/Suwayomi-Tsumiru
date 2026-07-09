// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../../constants/enum.dart';

/// Whether a reading mode is paged (page-flip) rather than continuous/webtoon
/// scroll. Single source of truth for the gesture routing and the bottom
/// controls, which must agree on what counts as "paged".
bool isPagedReaderMode(ReaderMode mode) => switch (mode) {
      ReaderMode.singleHorizontalLTR ||
      ReaderMode.singleHorizontalRTL ||
      ReaderMode.singleVertical ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        true,
      ReaderMode.defaultReader ||
      ReaderMode.continuousVertical ||
      ReaderMode.webtoon =>
        false,
    };
