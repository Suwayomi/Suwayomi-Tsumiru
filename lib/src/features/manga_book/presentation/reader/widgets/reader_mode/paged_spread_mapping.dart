// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Maps display spreads and split halves to raw page indices used by progress and seeking.
library;

enum PageHalf { full, left, right }

class PageUnit {
  const PageUnit(this.raw, {this.half = PageHalf.full});

  /// Raw index into `chapterPages.pages`.
  final int raw;

  final PageHalf half;

  @override
  bool operator ==(Object other) =>
      other is PageUnit && other.raw == raw && other.half == half;

  @override
  int get hashCode => Object.hash(raw, half);

  @override
  String toString() => 'PageUnit($raw, ${half.name})';
}

class SpreadEntry {
  const SpreadEntry(this.first, [this.second]);

  final PageUnit first;
  final PageUnit? second;

  bool get isPair => second != null;

  /// The RAW source page reported outward for this display position — always
  /// the reading-first source page (seekbar contract).
  int get primaryRaw => first.raw;

  /// Report the furthest raw page in a spread so its final page can complete the chapter.
  int get progressRaw => second?.raw ?? first.raw;

  @override
  bool operator ==(Object other) =>
      other is SpreadEntry && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() =>
      'SpreadEntry($first${second == null ? '' : ', $second'})';
}

class SpreadMapping {
  const SpreadMapping(this.entries);

  final List<SpreadEntry> entries;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;

  /// Returns the reading-first raw page, clamping out-of-range display indices.
  int displayToRaw(int displayIndex) {
    if (entries.isEmpty) return 0;
    final i = displayIndex.clamp(0, entries.length - 1).toInt();
    return entries[i].primaryRaw;
  }

  /// Returns the furthest raw page for progress, clamping like [displayToRaw].
  int displayToProgressRaw(int displayIndex) {
    if (entries.isEmpty) return 0;
    final i = displayIndex.clamp(0, entries.length - 1).toInt();
    return entries[i].progressRaw;
  }

  /// Matches either page of a pair; split pages resolve to their first half.
  int rawToDisplay(int rawIndex) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.first.raw == rawIndex || e.second?.raw == rawIndex) return i;
    }
    return 0;
  }
}

/// Pairs units when [doublePages]; wide pages split with [splitWide], otherwise stay solo; unknown width is false.
SpreadMapping buildSpreadMapping({
  required int pageCount,
  required bool doublePages,
  required bool splitWide,
  required bool splitInvert,
  required bool Function(int raw) isWide,
}) {
  if (pageCount <= 0) return const SpreadMapping([]);

  final units = <PageUnit>[];
  for (var raw = 0; raw < pageCount; raw++) {
    if (splitWide && isWide(raw)) {
      final firstHalf = splitInvert ? PageHalf.right : PageHalf.left;
      final secondHalf = splitInvert ? PageHalf.left : PageHalf.right;
      units.add(PageUnit(raw, half: firstHalf));
      units.add(PageUnit(raw, half: secondHalf));
    } else {
      units.add(PageUnit(raw));
    }
  }

  if (!doublePages) {
    return SpreadMapping([for (final u in units) SpreadEntry(u)]);
  }

  // Full wide pages break pairing; split halves pair normally.
  bool wideSolo(PageUnit u) => u.half == PageHalf.full && isWide(u.raw);

  final entries = <SpreadEntry>[];
  var i = 0;
  while (i < units.length) {
    final u = units[i];
    if (wideSolo(u)) {
      entries.add(SpreadEntry(u));
      i++;
      continue;
    }
    if (i + 1 < units.length && !wideSolo(units[i + 1])) {
      entries.add(SpreadEntry(u, units[i + 1]));
      i += 2;
      continue;
    }
    entries.add(SpreadEntry(u));
    i++;
  }
  return SpreadMapping(entries);
}
