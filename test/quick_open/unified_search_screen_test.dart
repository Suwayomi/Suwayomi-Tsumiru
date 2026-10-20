import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

CategoryDto _cat(int id, String name) => Fragment$CategoryDto(
  defaultCategory: false,
  id: id,
  includeInDownload: Enum$IncludeOrExclude.UNSET,
  includeInUpdate: Enum$IncludeOrExclude.UNSET,
  name: name,
  order: id,
  mangas: Fragment$CategoryDto$mangas(totalCount: 5),
  meta: const [],
);

// Override the data providers so the test never hits the real GraphQL/offline
// or SharedPreferences stack. `all` is the raw category list; `visible` is the
// filtered set (non-empty + not-hidden) the screen MUST use — the split lets
// us prove the screen reads visibleCategoryListProvider, not the raw list.
Future<Widget> _host({
  List<CategoryDto> visible = const [],
  List<CategoryDto> all = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      libraryMangaListProvider.overrideWith((ref) async => const []),
      categoryControllerProvider.overrideWith(() => _Categories(all)),
      visibleCategoryListProvider.overrideWith((ref) => AsyncData(visible)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UnifiedSearchScreen(afterClick: () {})),
    ),
  );
}

class _Categories extends CategoryController {
  _Categories(this._categories);
  final List<CategoryDto> _categories;
  @override
  Future<List<CategoryDto>?> build() async => _categories;
}

void main() {
  testWidgets('the go-to list uses visible categories, not the raw list', (
    tester,
  ) async {
    // 'Pornhwa' is in the raw list but NOT the visible set (it's hidden).
    // Mirrors the reported repro: typing the hidden category's name.
    await tester.pumpWidget(
      await _host(
        visible: [_cat(2, 'Seinen')],
        all: [_cat(2, 'Seinen'), _cat(3, 'Pornhwa')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'porn');
    await tester.pumpAndSettle();
    expect(
      find.text('Pornhwa'),
      findsNothing,
      reason: 'hidden category must not appear even when searched',
    );

    await tester.enterText(find.byType(TextField), 'sein');
    await tester.pumpAndSettle();
    expect(
      find.text('Seinen'),
      findsOneWidget,
      reason: 'visible category is searchable',
    );
  });
}
