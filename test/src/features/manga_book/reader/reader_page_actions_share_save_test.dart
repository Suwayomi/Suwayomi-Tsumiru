// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reader page-actions sheet: on mobile the sheet shows a single-page
// set — Copy (image), Share image, Save to gallery — and does NOT show the
// desktop-only "Open in web" fallback. The tiles are gated to Android/iOS (gal +
// the image-clipboard channel are mobile-only), so this test drives the mobile
// path via debugDefaultTargetPlatformOverride. Tapping the tiles hits real
// platform channels that don't exist in a unit env, so we only assert the tiles
// render and are tappable — not that the share/save/copy actually completed.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_page_actions_sheet.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

ChapterPagesDto _pages() => ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
      pages: const [
        '/manga/1/chapter/0/page/0',
        '/manga/1/chapter/0/page/1',
        '/manga/1/chapter/0/page/2',
      ],
    );

const _copyKey = ValueKey('reader-page-action-copy-image');
const _openKey = ValueKey('reader-page-action-open-web');
const _shareKey = ValueKey('reader-page-action-share');
const _saveKey = ValueKey('reader-page-action-save');

Future<void> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Drive the mobile-only branch. Cleared again below (before the test body
  // returns) so the framework's post-test invariant check passes.
  debugDefaultTargetPlatformOverride = TargetPlatform.android;

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showReaderPageActionsSheet(
                  context: context,
                  ref: ref,
                  chapterPages: _pages(),
                  pageIndex: 0,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // isMobile has been evaluated during the pump; clear the override so it
  // doesn't leak into the framework's end-of-test invariant assertion.
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('mobile: Komikku set — Copy image, Share, Save; no Open in web',
      (tester) async {
    await _openSheet(tester);

    // Single-page actions on mobile; the desktop-only "Open in
    // web" fallback is hidden.
    expect(find.byKey(_copyKey), findsOneWidget);
    expect(find.byKey(_shareKey), findsOneWidget);
    expect(find.byKey(_saveKey), findsOneWidget);
    expect(find.byKey(_openKey), findsNothing);
  });

  testWidgets('mobile: Share and Save are tappable action buttons',
      (tester) async {
    await _openSheet(tester);

    final shareBtn = tester.widget<TextButton>(find.byKey(_shareKey));
    final saveBtn = tester.widget<TextButton>(find.byKey(_saveKey));

    expect(shareBtn.onPressed, isNotNull);
    expect(saveBtn.onPressed, isNotNull);
  });
}
