import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/sorayomi.dart';

void main() {
  testWidgets(
    'automatic scrollbars exclude horizontal and disabled scrolling',
    (tester) async {
      late BuildContext context;
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      const behavior = AppScrollBehavior();
      const child = SizedBox();
      for (final details in [
        const ScrollableDetails.horizontal(),
        const ScrollableDetails.vertical(
          physics: NeverScrollableScrollPhysics(),
        ),
        const ScrollableDetails.vertical(
          physics: ClampingScrollPhysics(
            parent: NeverScrollableScrollPhysics(),
          ),
        ),
      ]) {
        expect(behavior.buildScrollbar(context, child, details), same(child));
      }
      expect(
        behavior.buildScrollbar(
          context,
          child,
          const ScrollableDetails.vertical(),
        ),
        isA<Scrollbar>(),
      );
    },
  );

  test('expected chapter uses natural plural wording', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.seriesNextChapterExpected(0), 'Next chapter expected soon');
    expect(l10n.seriesNextChapterExpected(1), 'Next chapter expected in 1 day');
    expect(
      l10n.seriesNextChapterExpected(3),
      'Next chapter expected in 3 days',
    );
  });

  for (final width in [1400.0, 412.0]) {
    testWidgets('description arrow sits below the clipped preview at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var expanded = false;
      await tester.pumpWidget(
        _app(
          MangaDescriptionBody(
            description: 'A long description. ' * 100,
            isExpanded: false,
            onToggleExpanded: () => expanded = true,
          ),
        ),
      );
      final preview = tester.getRect(find.byType(SingleChildScrollView));
      final arrow = tester.getRect(
        find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      expect(arrow.top, greaterThanOrEqualTo(preview.bottom));
      expect(find.byType(Scrollbar), findsNothing);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      expect(expanded, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('collapsed markdown preview does not overflow', (tester) async {
    await tester.pumpWidget(
      _app(
        MangaDescriptionBody(
          description: [
            '# Heading',
            '',
            for (var i = 0; i < 12; i++)
              'Paragraph $i with enough text to wrap across the preview width.',
          ].join('\n\n'),
          isExpanded: false,
          onToggleExpanded: () {},
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('opens markdown links with the supplied callback', (
    tester,
  ) async {
    String? openedUrl;

    await tester.pumpWidget(
      _app(
        MangaDescriptionBody(
          description: '[Source](https://example.com/title)',
          isExpanded: true,
          onToggleExpanded: () {},
          onOpenLink: (url) => openedUrl = url,
        ),
      ),
    );

    await tester.tap(find.text('Source', findRichText: true));
    await tester.pump();

    expect(openedUrl, 'https://example.com/title');
  });
}

Widget _app(Widget child) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);
