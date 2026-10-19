// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// P2: resizing across the one-bar/two-row breakpoint must not remount the
// toolbar's stateful controls. The two layouts give the slot different
// ancestors (Container/Stack vs Column), which remounts the search field:
// its focus node dies, so focus and the open dropdown are lost on resize.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/desktop_search_field.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_title_bar.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

import '../../../helpers/unreachable_server_stubs.dart';

/// Merged at 1400 (208 + 10 + 700 + 10 + 138 + 10 = 1076), two rows at 900
/// (the sidebar auto-collapses to 60: 60 + 10 + 700 + 10 + 138 + 10 = 928).
const _mergedSize = Size(1400, 900);
const _twoRowSize = Size(900, 900);

Widget _boundField() => Consumer(
  builder: (context, ref, _) => DesktopSearchField(
    query: ref.watch(unifiedSearchQueryProvider),
    onChanged: (value) =>
        ref.read(unifiedSearchQueryProvider.notifier).state = value,
    onNavigate: () => ref.read(unifiedSearchQueryProvider.notifier).state = '',
  ),
);

Finder _fieldTextField() => find.descendant(
  of: find.byType(DesktopSearchField),
  matching: find.byType(TextField),
);

void main() {
  setUp(() => debugDesktopPlatformOverride = true);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets(
    'search keeps state, focus and text across the breakpoint both ways',
    (tester) async {
      tester.view.physicalSize = _mergedSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            if (call.method == 'isMaximized') return false;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            ),
      );
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          libraryMangaListProvider.overrideWith(
            (ref) async => const <Fragment$MangaDto>[],
          ),
          visibleCategoryListProvider.overrideWithValue(
            const AsyncData(<Fragment$CategoryDto>[]),
          ),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    if (showsMergedTopBar(context)) const DesktopTopBar(),
                    Expanded(
                      child: TopBarSlot(
                        minWidth: 700,
                        content: desktopSearchSlotContent(
                          search: _boundField(),
                          actions: const [],
                        ),
                        child: const Center(child: Text('page')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Merged layout at 1400: no standalone title row.
      expect(find.byType(DesktopTitleBar), findsNothing);

      await tester.tap(_fieldTextField());
      await tester.pumpAndSettle();
      await tester.enterText(_fieldTextField(), 'abc');
      await tester.pumpAndSettle();
      expect(container.read(unifiedSearchQueryProvider), 'abc');
      final State<StatefulWidget> before =
          tester.state(find.byType(DesktopSearchField));
      expect(
        tester.widget<TextField>(_fieldTextField()).focusNode?.hasFocus,
        isTrue,
      );

      // Across the breakpoint into two rows: same State, still focused, text
      // intact.
      tester.view.physicalSize = _twoRowSize;
      await tester.pumpAndSettle();
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(
        tester.state(find.byType(DesktopSearchField)),
        same(before),
      );
      expect(
        tester.widget<TextField>(_fieldTextField()).focusNode?.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<TextField>(_fieldTextField()).controller?.text,
        'abc',
      );

      // And back into one row: still the same State, focus and text.
      tester.view.physicalSize = _mergedSize;
      await tester.pumpAndSettle();
      expect(find.byType(DesktopTitleBar), findsNothing);
      expect(
        tester.state(find.byType(DesktopSearchField)),
        same(before),
      );
      expect(
        tester.widget<TextField>(_fieldTextField()).focusNode?.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<TextField>(_fieldTextField()).controller?.text,
        'abc',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
