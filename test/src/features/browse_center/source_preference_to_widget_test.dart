// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/source_preference/source_preference.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_preference/widgets/source_preference_to_widget.dart';

void main() {
  testWidgets('switch and checkbox preferences with no key or title render',
      (tester) async {
    // Servers may send a null title or key (schema: String, not String!);
    // matching those as non-nullable skipped every case and threw.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SourcePreferenceToWidget(
                index: 0,
                sourcePreference: SwitchPreferenceCompat(
                  switchDefaultValue: false,
                  switchValue: true,
                ),
                onChanged: (_) {},
              ),
              SourcePreferenceToWidget(
                index: 1,
                sourcePreference: CheckBoxPreference(
                  checkBoxDefaultValue: true,
                ),
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });
}
