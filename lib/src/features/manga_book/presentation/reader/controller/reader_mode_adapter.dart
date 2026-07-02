// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';

/// Parity chips for the Reading-mode row. Pure presentation: the stored
/// 8-value ReaderMode stays byte-for-byte; chips are a view over it (§2.5).
enum ReadingModeChip {
  defaultChip,
  pagedLTR,
  pagedRTL,
  pagedVertical,
  longStrip,
  longStripGaps;

  String toLocale(BuildContext context) => switch (this) {
        ReadingModeChip.defaultChip => context.l10n.readerModeChipDefault,
        ReadingModeChip.pagedLTR => context.l10n.readerModeChipPagedLtr,
        ReadingModeChip.pagedRTL => context.l10n.readerModeChipPagedRtl,
        ReadingModeChip.pagedVertical =>
          context.l10n.readerModeChipPagedVertical,
        ReadingModeChip.longStrip => context.l10n.readerModeChipLongStrip,
        ReadingModeChip.longStripGaps =>
          context.l10n.readerModeChipLongStripGaps,
      };
}

abstract final class ReaderModeAdapter {
  /// Null for the continuous-horizontal orphans: no parity chip lies about
  /// them — the sheet shows a dedicated "legacy" chip instead.
  static ReadingModeChip? toChip(ReaderMode mode) => switch (mode) {
        ReaderMode.defaultReader => ReadingModeChip.defaultChip,
        ReaderMode.singleHorizontalLTR => ReadingModeChip.pagedLTR,
        ReaderMode.singleHorizontalRTL => ReadingModeChip.pagedRTL,
        ReaderMode.singleVertical => ReadingModeChip.pagedVertical,
        ReaderMode.webtoon => ReadingModeChip.longStrip,
        ReaderMode.continuousVertical => ReadingModeChip.longStripGaps,
        ReaderMode.continuousHorizontalLTR ||
        ReaderMode.continuousHorizontalRTL =>
          null,
      };

  /// Never emits an orphan: tapping a parity chip is the only path off one.
  static ReaderMode fromChip(ReadingModeChip chip) => switch (chip) {
        ReadingModeChip.defaultChip => ReaderMode.defaultReader,
        ReadingModeChip.pagedLTR => ReaderMode.singleHorizontalLTR,
        ReadingModeChip.pagedRTL => ReaderMode.singleHorizontalRTL,
        ReadingModeChip.pagedVertical => ReaderMode.singleVertical,
        ReadingModeChip.longStrip => ReaderMode.webtoon,
        ReadingModeChip.longStripGaps => ReaderMode.continuousVertical,
      };

  static bool isLegacyOrphan(ReaderMode mode) => toChip(mode) == null;
}
