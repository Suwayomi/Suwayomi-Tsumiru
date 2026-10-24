// Series page backdrop default: on for single-column, off for two-column,
// until the user flips the Appearance switch and the override wins.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/widgets/manga_thumbnail_backdrop/manga_thumbnail_backdrop_tile.dart';

void main() {
  test('unset switch follows the layout, a set switch wins', () {
    expect(
      resolveMangaThumbnailBackdrop(override: null, twoColumn: false),
      isTrue,
    );
    expect(
      resolveMangaThumbnailBackdrop(override: null, twoColumn: true),
      isFalse,
    );
    expect(
      resolveMangaThumbnailBackdrop(override: true, twoColumn: true),
      isTrue,
    );
    expect(
      resolveMangaThumbnailBackdrop(override: false, twoColumn: false),
      isFalse,
    );
  });
}
