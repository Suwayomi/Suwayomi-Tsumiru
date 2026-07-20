// Enums persisted via SharedPreferenceEnumClientMixin store an index into
// Enum.values, so declaration order is a wire format — append new values at
// the end, don't reorder or insert, or you'll silently remap saved settings.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  // Expected declaration order (by name) for each index-persisted enum.
  const expected = <String, List<String>>{
    'AppTheme': [
      'indigoNight', 'carbon', 'plum', 'custom', 'regression', 'ember',
      'synthwave', 'terminal', 'catppuccin', 'nord', 'gruvbox', 'dracula',
      'mono', 'royal'
    ],
    'AuthType': ['none', 'basic', 'simpleLogin', 'uiLogin'],
    'CenterMarginType': ['none', 'doublePage', 'widePage', 'doubleAndWide'],
    'ChapterDisplay': ['sourceTitle', 'chapterNumber'],
    'ChapterSort': [
      'source', 'uploadDate', 'fetchedDate', 'chapterNumber', 'alphabetical'
    ],
    'ColorFilterBlendMode': [
      'defaultBlend', 'multiply', 'screen', 'overlay', 'lighten', 'darken'
    ],
    'DisplayMode': [
      'grid', 'list', 'descriptiveList', 'coverOnly', 'comfortableGrid'
    ],
    'FlashColor': ['black', 'white', 'whiteBlack'],
    'GlobalSearchSourceFilter': ['pinned', 'all'],
    'ImageScaleType': [
      'fitScreen', 'stretch', 'fitWidth', 'fitHeight', 'originalSize', 'smartFit'
    ],
    'MangaSort': [
      'alphabetical', 'dateAdded', 'unread', 'lastUpdated', 'lastChapterDate',
      'totalChapters', 'lastRead', 'random', 'trackerScore', 'lastUpdate',
      'rating'
    ],
    'PageLayout': ['singlePage', 'doublePages', 'automatic'],
    'ReaderBackgroundColor': ['white', 'black', 'gray', 'automatic'],
    'ReaderMode': [
      'defaultReader', 'continuousVertical', 'singleHorizontalLTR',
      'singleHorizontalRTL', 'continuousHorizontalLTR',
      'continuousHorizontalRTL', 'singleVertical', 'webtoon'
    ],
    'ReaderNavigationLayout': [
      'defaultNavigation', 'lShaped', 'rightAndLeft', 'edge', 'kindlish',
      'disabled'
    ],
    'ReaderOrientation': [
      'defaultRotation', 'free', 'portrait', 'landscape', 'lockedPortrait',
      'lockedLandscape', 'reversePortrait'
    ],
    'ReaderScrollAmount': ['tiny', 'small', 'medium', 'large'],
    'TapInvert': ['none', 'horizontal', 'vertical', 'both'],
    'ThemeMode': ['system', 'light', 'dark'],
    'WebtoonScaleType': [
      'fitScreen', 'ratio4to3', 'ratio3to2', 'ratio16to9', 'ratio20to9'
    ],
    'ZoomStart': ['automatic', 'left', 'right', 'center'],
  };

  final actual = <String, List<String>>{
    'AppTheme': AppTheme.values.map((e) => e.name).toList(),
    'AuthType': AuthType.values.map((e) => e.name).toList(),
    'CenterMarginType': CenterMarginType.values.map((e) => e.name).toList(),
    'ChapterDisplay': ChapterDisplay.values.map((e) => e.name).toList(),
    'ChapterSort': ChapterSort.values.map((e) => e.name).toList(),
    'ColorFilterBlendMode':
        ColorFilterBlendMode.values.map((e) => e.name).toList(),
    'DisplayMode': DisplayMode.values.map((e) => e.name).toList(),
    'FlashColor': FlashColor.values.map((e) => e.name).toList(),
    'GlobalSearchSourceFilter':
        GlobalSearchSourceFilter.values.map((e) => e.name).toList(),
    'ImageScaleType': ImageScaleType.values.map((e) => e.name).toList(),
    'MangaSort': MangaSort.values.map((e) => e.name).toList(),
    'PageLayout': PageLayout.values.map((e) => e.name).toList(),
    'ReaderBackgroundColor':
        ReaderBackgroundColor.values.map((e) => e.name).toList(),
    'ReaderMode': ReaderMode.values.map((e) => e.name).toList(),
    'ReaderNavigationLayout':
        ReaderNavigationLayout.values.map((e) => e.name).toList(),
    'ReaderOrientation': ReaderOrientation.values.map((e) => e.name).toList(),
    'ReaderScrollAmount': ReaderScrollAmount.values.map((e) => e.name).toList(),
    'TapInvert': TapInvert.values.map((e) => e.name).toList(),
    'ThemeMode': ThemeMode.values.map((e) => e.name).toList(),
    'WebtoonScaleType': WebtoonScaleType.values.map((e) => e.name).toList(),
    'ZoomStart': ZoomStart.values.map((e) => e.name).toList(),
  };

  for (final name in expected.keys) {
    test('$name index-persistence order is unchanged (append-only)', () {
      expect(actual[name], expected[name],
          reason: 'Reordering/inserting a value in $name remaps every saved '
              'preference. Append new values at the end instead.');
    });
  }
}
