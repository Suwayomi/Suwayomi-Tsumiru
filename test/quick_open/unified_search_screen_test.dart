import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

// Override the data providers so the test never hits the real GraphQL/offline
// stack (a bare ProviderScope would run real fetches → flaky / pumpAndSettle stall).
Widget _host() => ProviderScope(
      overrides: [
        libraryMangaListProvider.overrideWith((ref) async => const []),
        categoryControllerProvider.overrideWith(() => _EmptyCategories()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: UnifiedSearchScreen(afterClick: () {})),
      ),
    );

class _EmptyCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => const [];
}

void main() {
  testWidgets('typing shows the Go to section and an all-sources row',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.enterText(find.byType(TextField), 'reader');
    await tester.pumpAndSettle();

    expect(find.text('Go to'), findsOneWidget);
    expect(find.textContaining('Search all sources'), findsOneWidget);
  });

  testWidgets('empty query shows neither section', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Go to'), findsNothing);
    expect(find.textContaining('Search all sources'), findsNothing);
  });
}
