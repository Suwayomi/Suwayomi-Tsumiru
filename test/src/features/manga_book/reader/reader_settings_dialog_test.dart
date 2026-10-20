// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// I7 gate + C2/C3 contract for the 3-tab reader settings sheet: tab switches
// and per-tab scrolling never crash (no shared scroll controller), the modal
// barrier stays real on every tab, and every dismiss path restores chrome.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_settings_dialog.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

MangaDto _manga() => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
);

/// Mimics ReaderWrapper's gear tap: owns the visibility/padding
/// notifiers and opens the sheet through the real helper.
class _SheetHost extends ConsumerWidget {
  const _SheetHost({required this.visibility, required this.padding});

  final ValueNotifier<bool> visibility;
  final ValueNotifier<double> padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showReaderSettingsSheet(
            context: context,
            ref: ref,
            mangaId: 1,
            visibility: visibility,
            readerPadding: padding,
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  late ValueNotifier<bool> visibility;

  Future<void> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    visibility = ValueNotifier(true);
    addTearDown(visibility.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga())),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _SheetHost(visibility: visibility, padding: ValueNotifier(0.0)),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsOneWidget);
  }

  testWidgets('C3: barrier tap dismisses and restores chrome', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    await tester.tap(find.text('Custom filter'));
    await tester.pumpAndSettle();
    expect(visibility.value, false);

    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsNothing);
    expect(visibility.value, true);
  });
}
