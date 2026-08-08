// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// The bar and the rail badge through one helper so the two layouts can't drift
// apart, and a badge on the wrong tab is worse than no badge at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/animated_nav_vectors.dart';
import 'package:tsumiru/src/constants/navigation_bar_data.dart';
import 'package:tsumiru/src/widgets/shell/nav_badges.dart';

const _marker = SizedBox.shrink();

NavigationBarData _tab(IconData icon) => NavigationBarData(
  icon: icon,
  activeIcon: icon,
  animatedIcon: AnimatedNavVectors.browse,
  label: (_) => 'tab',
);

void main() {
  final browse = _tab(Icons.explore_outlined);
  final downloads = _tab(Icons.download_outlined);
  final library = _tab(Icons.collections_bookmark_outlined);

  test('Browse carries the count of extensions with updates', () {
    final badged = badgedNavIcon(_marker, browse, false, 3);
    expect(badged, isA<Badge>());
    expect(((badged as Badge).label as Text).data, '3');
  });

  test('no updates means no badge', () {
    expect(badgedNavIcon(_marker, browse, false, 0), same(_marker));
  });

  test('the extension count never lands on another tab', () {
    expect(badgedNavIcon(_marker, library, false, 5), same(_marker));
    // Downloads shows its own paused dot, and it must stay a dot — a count of
    // extension updates on the Downloads tab would be actively misleading.
    final pausedDownloads = badgedNavIcon(_marker, downloads, true, 5);
    expect((pausedDownloads as Badge).label, isNull);
  });

  test('Downloads badges only while paused', () {
    expect(badgedNavIcon(_marker, downloads, true, 0), isA<Badge>());
    expect(badgedNavIcon(_marker, downloads, false, 0), same(_marker));
  });
}
