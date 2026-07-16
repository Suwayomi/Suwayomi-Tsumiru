import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_title_bar.dart';

void main() {
  testWidgets('renders at the fixed bar height with the theme surface color',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          colorScheme: const ColorScheme.dark(surface: Color(0xFF0B0D1A))),
      home: const Scaffold(body: DesktopTitleBar()),
    ));
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DesktopTitleBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(container.color, const Color(0xFF0B0D1A));
    final size = tester.getSize(find.byType(DesktopTitleBar));
    expect(size.height, kDesktopTitleBarHeight);
  });
}
