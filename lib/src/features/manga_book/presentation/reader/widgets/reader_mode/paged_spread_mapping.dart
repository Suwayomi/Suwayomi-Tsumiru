// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Pure display-list mapping for the horizontal paged viewer.
///
/// The paged PageView reports the RAW page index outward (read-tracking,
/// seekbar "N / M", jumpToPage). Double-page / dual-split change what a
/// PageView *item* is — a spread (two pages) or a half of a wide page — so
/// this builds an internal DISPLAY LIST and translates display-index ↔
/// raw-page. Kept pure (no Flutter deps) so the index contract is unit-tested.
///
/// Double-page mode chunks pages into pairs, isolating wide pages as their
/// own full-width "solo" spread, then splits them for dual-page view.
library;

/// Which portion of a source page a display slot renders.
enum PageHalf { full, left, right }

/// One source-page fragment occupying a slot in a display entry.
class PageUnit {
  const PageUnit(this.raw, {this.half = PageHalf.full});

  /// Raw index into `chapterPages.pages`.
  final int raw;

  /// full page, or a split half of a wide page (before invert is applied).
  final PageHalf half;

  @override
  bool operator ==(Object other) =>
      other is PageUnit && other.raw == raw && other.half == half;

  @override
  int get hashCode => Object.hash(raw, half);

  @override
  String toString() => 'PageUnit($raw, ${half.name})';
}

/// A single PageView item: one or two [PageUnit]s shown side by side.
class SpreadEntry {
  const SpreadEntry(this.first, [this.second]);

  final PageUnit first;
  final PageUnit? second;

  bool get isPair => second != null;

  /// The RAW source page reported outward for this display position — always
  /// the reading-first source page (seekbar contract).
  int get primaryRaw => first.raw;

  /// The furthest raw page in this slot (read-progress). A spread shows both
  /// pages, so progress is the last, not the first — else a double-page
  /// chapter's final spread never reports its last page and never marks read.
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

/// The built display list plus the display↔raw translation the viewer needs.
class SpreadMapping {
  const SpreadMapping(this.entries);

  final List<SpreadEntry> entries;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;

  /// display position → raw source page (the primary/reading-first page).
  /// Clamped so an out-of-range controller page never throws.
  int displayToRaw(int displayIndex) {
    if (entries.isEmpty) return 0;
    final i = displayIndex.clamp(0, entries.length - 1).toInt();
    return entries[i].primaryRaw;
  }

  /// display position → the furthest raw page it shows (read-progress contract,
  /// see [SpreadEntry.progressRaw]). Clamped like [displayToRaw].
  int displayToProgressRaw(int displayIndex) {
    if (entries.isEmpty) return 0;
    final i = displayIndex.clamp(0, entries.length - 1).toInt();
    return entries[i].progressRaw;
  }

  /// raw source page → display position that shows it. Matches either slot, so
  /// jumpToPage(rawSecondOfPair) lands on the pair that contains it; a wide
  /// split page (two entries share the raw) lands on its first half.
  int rawToDisplay(int rawIndex) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.first.raw == rawIndex || e.second?.raw == rawIndex) return i;
    }
    return 0;
  }
}

/// Builds the display list.
///
/// - [pageCount]: raw page count.
/// - [doublePages]: pair consecutive units side by side (resolved from
///   pageLayout / automatic-orientation / trueDualPageSpread by the caller).
/// - [splitWide]: split each WIDE page into two half units.
/// - [splitInvert]: swap which half of a split wide page shows first.
/// - [isWide]: predicate — is raw page N a wide (landscape) page. Unknown pages
///   should return false; the viewer refines this as image dims resolve.
SpreadMapping buildSpreadMapping({
  required int pageCount,
  required bool doublePages,
  required bool splitWide,
  required bool splitInvert,
  required bool Function(int raw) isWide,
}) {
  if (pageCount <= 0) return const SpreadMapping([]);

  // Stage A — split: a wide page becomes two consecutive half units.
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

  // Stage B — single: one entry per unit.
  if (!doublePages) {
    return SpreadMapping([for (final u in units) SpreadEntry(u)]);
  }

  // Stage B — double: greedily pair units. A full-width WIDE page isolates
  // (solos) and breaks the pairing run. Split halves are
  // never "wide" (half != full) so they pair normally.
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
