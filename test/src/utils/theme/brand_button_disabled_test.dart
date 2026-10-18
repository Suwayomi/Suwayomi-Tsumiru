import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/utils/theme/app_theme_builder.dart';
import 'package:tsumiru/src/utils/theme/brand.dart';

ThemeData testTheme() => buildAppTheme(
  theme: AppTheme.indigoNight,
  brightness: Brightness.dark,
  customSeed: const Color(0xFF7C7BFF),
  amoled: false,
);

Future<void> pumpButton(WidgetTester tester, Widget button) {
  return tester.pumpWidget(
    MaterialApp(
      theme: testTheme(),
      home: Scaffold(body: button),
    ),
  );
}

BoxDecoration decorationOf<T extends Widget>(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: find.byType(T), matching: find.byType(DecoratedBox)),
  );
  return box.decoration as BoxDecoration;
}

Widget captureLabel(String text, void Function(Color?) onColor) {
  return Builder(
    builder: (context) {
      onColor(DefaultTextStyle.of(context).style.color);
      return Text(text);
    },
  );
}

void main() {
  testWidgets('BrandButton enabled has gradient and glow', (tester) async {
    Color? labelColor;
    await pumpButton(
      tester,
      BrandButton(
        onPressed: () {},
        label: captureLabel('Enabled', (c) => labelColor = c),
      ),
    );
    final decoration = decorationOf<BrandButton>(tester);
    expect(decoration.gradient, isNotNull);
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
    expect(labelColor, isNotNull);
  });

  testWidgets('BrandButton disabled drops gradient and glow', (tester) async {
    Color? labelColor;
    await pumpButton(
      tester,
      BrandButton(
        onPressed: null,
        label: captureLabel('Disabled', (c) => labelColor = c),
      ),
    );
    final theme = testTheme();
    final cs = theme.colorScheme;
    final decoration = decorationOf<BrandButton>(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.color, cs.onSurface.withValues(alpha: 0.12));
    expect(decoration.boxShadow == null || decoration.boxShadow!.isEmpty, true);
    expect(labelColor, cs.onSurface.withValues(alpha: 0.38));
  });

  testWidgets('BrandButton loading keeps gradient and glow', (tester) async {
    await pumpButton(
      tester,
      const BrandButton(onPressed: null, loading: true, label: Text('Busy')),
    );
    final decoration = decorationOf<BrandButton>(tester);
    expect(decoration.gradient, isNotNull);
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('BrandGlassButton disabled dims label only', (tester) async {
    final theme = testTheme();
    final cs = theme.colorScheme;

    Color? disabledLabel;
    await pumpButton(
      tester,
      BrandGlassButton(
        onPressed: null,
        label: captureLabel('Glass', (c) => disabledLabel = c),
      ),
    );
    expect(disabledLabel, cs.onSurface.withValues(alpha: 0.38));

    Color? enabledLabel;
    await pumpButton(
      tester,
      BrandGlassButton(
        onPressed: () {},
        label: captureLabel('Glass', (c) => enabledLabel = c),
      ),
    );
    expect(enabledLabel, brandBrightAccent(cs));
  });
}
