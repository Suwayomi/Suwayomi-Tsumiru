// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/source_filter_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

SourceDto _src({
  required String id,
  required String name,
  String lang = 'en',
  bool nsfw = false,
  bool hidden = false,
}) =>
    SourceDto.fromJson({
      'displayName': name,
      'iconUrl': '',
      'id': id,
      'isConfigurable': false,
      'isNsfw': nsfw,
      'lang': lang,
      'name': name,
      'supportsLatest': true,
      '__typename': 'SourceType',
      'meta': [
        if (hidden)
          {
            'key': 'tsumiru_isHidden',
            'value': 'true',
            '__typename': 'SourceMetaType',
          },
      ],
      'extension': {
        'pkgName': 'pkg',
        'repo': 'repo',
        '__typename': 'ExtensionType',
      },
    });

Future<Widget> _harness(Map<String, List<SourceDto>> byLang) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      allSourcesByLanguageProvider.overrideWith((ref) => AsyncData(byLang)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SourceFilterScreen(),
    ),
  );
}

void main() {
  testWidgets('renders Komikku structure: language switch, All Sources switch, '
      'per-source checkbox with flag', (tester) async {
    // Default enabled langs include "en" (not "ko"), so en expands and ko does not.
    await tester.pumpWidget(await _harness({
      'en': [_src(id: '1', name: 'Asura Scans')],
      'ko': [_src(id: '2', name: 'Manatoki', lang: 'ko')],
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Title "Sources".
    expect(find.widgetWithText(AppBar, 'Sources'), findsOneWidget);

    // Language rows are switches (not checkboxes) with flag in the title.
    expect(find.textContaining('English (English'), findsOneWidget);
    expect(find.textContaining('🇺🇸'), findsWidgets);
    expect(find.byType(SwitchListTile), findsWidgets);

    // en is enabled -> its "All Sources" switch + the source row show.
    expect(find.textContaining('All Sources'), findsOneWidget);
    expect(find.text('Asura Scans'), findsOneWidget);
    // per-source control is a Checkbox on the trailing side, checked = shown.
    final box = tester.widget<Checkbox>(find.descendant(
      of: find.widgetWithText(ListTile, 'Asura Scans'),
      matching: find.byType(Checkbox),
    ));
    expect(box.value, isTrue);

    // ko is disabled by default -> only the language switch, no source row.
    expect(find.text('Manatoki'), findsNothing);
  });

  testWidgets('enabled languages sort above disabled ones', (tester) async {
    // "en" is enabled by default, "af" (Afrikaans) is not — English must
    // render above Afrikaans even though "af" sorts first alphabetically.
    await tester.pumpWidget(await _harness({
      'af': [_src(id: '1', name: 'AfrikaSource', lang: 'af')],
      'en': [_src(id: '2', name: 'Asura Scans')],
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final englishY =
        tester.getTopLeft(find.textContaining('English (English')).dy;
    final afrikaansY =
        tester.getTopLeft(find.textContaining('Afrikaans (Afrikaans')).dy;
    expect(englishY, lessThan(afrikaansY));
  });

  testWidgets('a hidden source shows an unchecked box', (tester) async {
    await tester.pumpWidget(await _harness({
      'en': [_src(id: '1', name: 'Asura Scans', hidden: true)],
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final box = tester.widget<Checkbox>(find.descendant(
      of: find.widgetWithText(ListTile, 'Asura Scans'),
      matching: find.byType(Checkbox),
    ));
    expect(box.value, isFalse);
  });
}
