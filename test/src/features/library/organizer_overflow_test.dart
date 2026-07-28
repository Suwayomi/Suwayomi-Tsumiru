// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The organizer caps its content at a share of the WHOLE screen, but the sheet
/// it lives in gets less than that whenever a strip appears above the page —
/// the "Updating library" banner is a sibling of the page content. This is the
/// shape of that column; it has to give way rather than overflow.
Widget _organizerShape({required double capHeight, required Widget content}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 46, child: Placeholder()), // tab bar
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: capHeight),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('the organizer gives way when the sheet has less room than its cap',
      (tester) async {
    tester.view.physicalSize = const Size(412, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Cap says 500, the sheet only has 300 minus the tab bar, and the content
    // wants 800 — the exact squeeze the update banner creates.
    await tester.pumpWidget(_organizerShape(
      capHeight: 500,
      content: ListView(
        shrinkWrap: true,
        children: [for (var i = 0; i < 40; i++) SizedBox(height: 20, child: Text('$i'))],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'the organizer column overflowed instead of shrinking');
  });
}
