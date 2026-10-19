// test/theme/inter_font_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/constants/inter_license.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';

ThemeData themeFor(AppTheme theme, Brightness brightness) => buildAppTheme(
  theme: theme,
  brightness: brightness,
  customSeed: const Color(0xFF7C7BFF),
  amoled: false,
);

void main() {
  testWidgets('app text renders in Inter', (tester) async {
    for (final entry in [
      (AppTheme.indigoNight, Brightness.dark),
      (AppTheme.royal, Brightness.light),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(entry.$1, entry.$2),
          home: const Scaffold(body: Text('check')),
        ),
      );
      final style = DefaultTextStyle.of(
        tester.element(find.text('check')),
      ).style;
      expect(style.fontFamily, 'Inter');
    }
  });

  test('custom theme uses Inter too', () {
    expect(
      themeFor(AppTheme.custom, Brightness.dark).textTheme.bodyMedium?.fontFamily,
      'Inter',
    );
  });

  test("Inter OFL is in the licence list", () async {
    registerInterLicense();
    final entries = await LicenseRegistry.licenses.toList();
    final inter = entries
        .where((entry) => entry.packages.contains('Inter'))
        .toList();
    expect(inter, isNotEmpty);
    expect(
      inter
          .expand((entry) => entry.paragraphs)
          .map((paragraph) => paragraph.text)
          .join(),
      contains('SIL Open Font License'),
    );
  });
}
