// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

/// RTL swaps horizontal previous/next buttons; null callbacks disable unavailable directions.
({VoidCallback? leading, VoidCallback? trailing}) chapterNavCallbacks({
  required bool isRtl,
  required VoidCallback? onPreviousChapter,
  required VoidCallback? onNextChapter,
}) =>
    isRtl
        ? (leading: onNextChapter, trailing: onPreviousChapter)
        : (leading: onPreviousChapter, trailing: onNextChapter);
