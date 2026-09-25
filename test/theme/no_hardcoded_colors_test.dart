// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A colour written into app UI as a literal ignores the active theme: it stays
/// the same in light and dark, and on a light surface `Colors.grey` lands near
/// 2.5:1. Theme-aware code reads the ColorScheme, `BrandColors` or `OnImage`.
///
/// `Colors.transparent` is neither light nor dark, so it passes.
///
/// The `\b` before `Colors` is load-bearing: without it `BrandColors.of(...)`
/// reads as a `Colors.` hit.
final _literalColor = RegExp(
  r'\bColors\.(?!transparent\b)[a-zA-Z]+|Color\(0x|Color\.fromARGB|Color\.fromRGBO',
);

/// Files whose literal colours are deliberate, each with its reason. Adding an
/// entry means the colours there really are theme-independent — app UI that
/// follows light/dark belongs on a scheme role instead.
const _allowlist = <String, String>{
  'lib/src/constants/animated_nav_vectors.dart':
      'vector fills, tinted at draw time by animated_nav_icon.dart',
  'lib/src/constants/app_theme.dart': 'theme picker swatches',
  'lib/src/constants/db_keys.dart': 'default custom seed',
  'lib/src/constants/enum.dart': 'reader page background choices',
  'lib/src/features/manga_book/presentation/reader/widgets/chrome/reader_settings_dialog.dart':
      'reader canvas and overlays over pages',
  'lib/src/features/manga_book/presentation/reader/widgets/chrome/reader_flash_overlay.dart':
      'reader canvas and overlays over pages',
  'lib/src/features/manga_book/presentation/reader/widgets/chrome/reader_color_overlays.dart':
      'reader canvas and overlays over pages',
  'lib/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/reader_navigation_layout.dart':
      'reader canvas and overlays over pages',
  'lib/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart':
      'progress bar over cover',
  'lib/src/features/migration/presentation/screens/migration_bulk_run_screen.dart':
      'scrim over cover',
  'lib/src/features/manga_book/presentation/manga_details/manga_details_screen.dart':
      'overlay over cover art',
  'lib/src/features/settings/presentation/appearance/widgets/is_true_black/is_true_black_tile.dart':
      'the black swatch for the pure-black option',
};

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.graphql.dart') ||
    path.contains('/__generated__/');

void main() {
  test('app UI takes its colours from the theme, not from literals', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_isGenerated(path)) continue;
      // The theme itself is where the literal colours belong.
      if (path.startsWith('lib/src/utils/theme/')) continue;
      if (_allowlist.containsKey(path)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_literalColor.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Hard-coded colours do not follow the light/dark theme. Use a '
          'ColorScheme role, BrandColors.of(context) or OnImage instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
