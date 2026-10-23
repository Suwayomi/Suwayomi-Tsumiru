// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/input_popup/domain/settings_prop_type.dart';
import 'package:tsumiru/src/widgets/input_popup/settings_prop_tile.dart';

const _description =
    'Keeps the reader open on the last chapter you finished so you can pick up where you left off after restarting the app on any device.';

Future<void> _pump(WidgetTester tester, SettingsPropType type) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: SettingsPropTile(
              title: 'Resume reading',
              description: _description,
              type: type,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectWrapped(WidgetTester tester) {
  final text = tester.widget<Text>(find.text(_description));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(_description),
  );
  final oneLine = TextPainter(
    text: TextSpan(text: 'Ag', style: paragraph.text.style),
    textDirection: TextDirection.ltr,
  )..layout();

  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.height, greaterThan(oneLine.height * 1.5));
  expect(find.byType(Tooltip), findsNothing);
}

void main() {
  testWidgets('switch setting description wraps instead of cutting off', (
    tester,
  ) async {
    await _pump(tester, const SettingsPropType.switchTile(value: true));
    _expectWrapped(tester);
  });

  testWidgets('non-switch setting description wraps instead of cutting off', (
    tester,
  ) async {
    await _pump(tester, const SettingsPropType.textField(value: 'x'));
    _expectWrapped(tester);
  });
}
