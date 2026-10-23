// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Custom-filter tab parity contract: toggles reveal
// their sliders/chips, slider drags write ONLY the preview channel until
// onChangeEnd commits to the global providers, blend chips write, and sheet
// dismissal flushes an interrupted draft.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_preview_channel.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_settings_dialog.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_filter_prefs/reader_filter_prefs.dart';
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
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

/// Mimics ReaderWrapper's gear tap for the dismiss-flush test.
class _SheetHost extends ConsumerWidget {
  const _SheetHost({required this.visibility});

  final ValueNotifier<bool> visibility;

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
            readerPadding: ValueNotifier(0.0),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
  });

  testWidgets('sheet dismissal flushes a live draft to the provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'customBrightness': true});
    final prefs = await SharedPreferences.getInstance();
    final visibility = ValueNotifier(true);
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
          home: _SheetHost(visibility: visibility),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsOneWidget);

    // A drag interrupted by dismissal: the draft never saw onChangeEnd.
    readerBrightnessPreview.value = -30;

    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsDialog), findsNothing);

    final scope = ProviderScope.containerOf(
      tester.element(find.byType(_SheetHost)),
    );
    expect(
      scope.read(customBrightnessValueProvider),
      -30,
      reason: 'dismiss flushes the interrupted draft',
    );
    expect(readerBrightnessPreview.value, isNull);
  });
}
