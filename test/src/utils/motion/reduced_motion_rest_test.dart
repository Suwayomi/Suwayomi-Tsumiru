import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

Widget _app(Widget home, {required bool reduce}) => ProviderScope(
  overrides: [
    if (reduce) appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
  ],
  child: MaterialApp(
    builder: (context, child) => ReduceMotionScope(child: child!),
    home: Scaffold(body: home),
  ),
);

class _TabsSite extends StatelessWidget {
  const _TabsSite();

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    animationDuration: context.reduceMotion
        ? Duration.zero
        : kTabScrollDuration,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'first'),
            Tab(text: 'second'),
          ],
        ),
        const Expanded(
          child: TabBarView(
            children: [Text('first page'), Text('second page')],
          ),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'reduced motion shows the loading placeholder without a shimmer sweep',
    (tester) async {
      await tester.pumpWidget(
        _app(const SorayomiShimmerIndicator(), reduce: true),
      );
      await tester.pump();

      expect(find.byType(Shimmer), findsNothing);
      expect(
        tester.widget<ImageIcon>(find.byType(ImageIcon)).color,
        Theme.of(
          tester.element(find.byType(SorayomiShimmerIndicator)),
        ).colorScheme.primary,
      );
    },
  );

  testWidgets('without reduced motion the loading placeholder shimmers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const SorayomiShimmerIndicator(), reduce: false),
    );
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets(
    'reduced motion shows the delayed placeholder at full opacity at once',
    (tester) async {
      await tester.pumpWidget(_app(const DelayedShimmer(), reduce: true));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(DelayedShimmer),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(DelayedShimmer),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
    },
  );

  testWidgets(
    'without reduced motion the delayed placeholder is still fading in after one frame',
    (tester) async {
      await tester.pumpWidget(_app(const DelayedShimmer(), reduce: false));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(DelayedShimmer),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        lessThan(1),
      );
    },
  );

  testWidgets('reduced motion switches tabs at once', (tester) async {
    await tester.pumpWidget(_app(const _TabsSite(), reduce: true));
    await tester.tap(find.text('second'));
    await tester.pump();

    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    expect(find.text('second page'), findsOneWidget);
  });

  testWidgets(
    'without reduced motion a tab switch is still in progress after one frame',
    (tester) async {
      await tester.pumpWidget(_app(const _TabsSite(), reduce: false));
      await tester.tap(find.text('second'));
      await tester.pump();

      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        lessThan(1),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
    },
  );
}
