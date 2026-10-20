// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/edit_mangas_category_dialog.dart';

void main() {
  group('categoryMembership (bulk category tri-state)', () {
    test('all selected series in the category → true', () {
      expect(
        categoryMembership([
          {1, 2},
          {1, 3},
          {1},
        ], 1),
        isTrue,
      );
    });

    test('no selected series in the category → false', () {
      expect(
        categoryMembership([
          {2, 3},
          {4},
        ], 1),
        isFalse,
      );
    });

    test('some in, some out → null (mixed)', () {
      expect(
        categoryMembership([
          {1, 2},
          {3},
          {1},
        ], 1),
        isNull,
      );
    });
  });
}
