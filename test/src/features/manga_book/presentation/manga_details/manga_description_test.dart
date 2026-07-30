import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/manga_description.dart';

void main() {
  testWidgets('collapsed markdown preview does not overflow', (tester) async {
    await tester.pumpWidget(_app(
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
    ));

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('opens markdown links with the supplied callback',
      (tester) async {
    String? openedUrl;

    await tester.pumpWidget(_app(
      MangaDescriptionBody(
        description: '[Source](https://example.com/title)',
        isExpanded: true,
        onToggleExpanded: () {},
        onOpenLink: (url) => openedUrl = url,
      ),
    ));

    await tester.tap(find.text('Source', findRichText: true));
    await tester.pump();

    expect(openedUrl, 'https://example.com/title');
  });
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
