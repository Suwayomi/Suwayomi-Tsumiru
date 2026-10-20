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
  testWidgets('BrandButton states: enabled, disabled and loading', (
    tester,
  ) async {
    Color? enabledLabel;
    await pumpButton(
      tester,
      BrandButton(
        onPressed: () {},
        label: captureLabel('Enabled', (c) => enabledLabel = c),
      ),
    );
    final enabled = decorationOf<BrandButton>(tester);
    expect(enabled.gradient, isNotNull);
    expect(enabled.boxShadow, isNotNull);
    expect(enabled.boxShadow, isNotEmpty);
    expect(enabledLabel, isNotNull);

    Color? disabledLabel;
    await pumpButton(
      tester,
      BrandButton(
        onPressed: null,
        label: captureLabel('Disabled', (c) => disabledLabel = c),
      ),
    );
    final cs = testTheme().colorScheme;
    final disabled = decorationOf<BrandButton>(tester);
    expect(disabled.gradient, isNull);
    expect(disabled.color, cs.onSurface.withValues(alpha: 0.12));
    expect(disabled.boxShadow == null || disabled.boxShadow!.isEmpty, true);
    expect(disabledLabel, cs.onSurface.withValues(alpha: 0.38));

    await pumpButton(
      tester,
      const BrandButton(onPressed: null, loading: true, label: Text('Busy')),
    );
    final loading = decorationOf<BrandButton>(tester);
    expect(loading.gradient, isNotNull);
    expect(loading.boxShadow, isNotNull);
    expect(loading.boxShadow, isNotEmpty);
  });

  testWidgets('BrandGlassButton disabled dims the label only', (tester) async {
    final cs = testTheme().colorScheme;

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
