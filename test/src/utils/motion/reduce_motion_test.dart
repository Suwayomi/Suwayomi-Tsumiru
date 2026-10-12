import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

const _nextKey = ValueKey('next');

class _Probe {
  bool? reduceMotion;
  ThemeData? theme;
  BuildContext? context;
}

Widget _app(_Probe probe, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      builder: (context, child) => ReduceMotionScope(child: child!),
      home: Builder(
        builder: (context) {
          probe
            ..reduceMotion = context.reduceMotion
            ..theme = Theme.of(context)
            ..context = context;
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(key: _nextKey, body: Text('next')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

bool _hasTransitionAbove(WidgetTester tester, Finder page) {
  return tester
      .widgetList(
        find.ancestor(
          of: page,
          matching: find.byWidgetPredicate(
            (w) => w is FadeTransition || w is SlideTransition,
          ),
        ),
      )
      .isNotEmpty;
}

Future<void> _pushNext(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  // The pushed route is built on the frame after the Navigator inserts it.
  await tester.pump();
  await tester.pump();
}

void _expectReduced(_Probe probe) {
  expect(probe.reduceMotion, isTrue);
  expect(probe.theme!.splashFactory, NoSplash.splashFactory);
  expect(
    probe.theme!.expansionTileTheme.expansionAnimationStyle,
    AnimationStyle.noAnimation,
  );
}

Future<void> _expectPageAppearsInstantly(WidgetTester tester) async {
  await _pushNext(tester);
  expect(find.byKey(_nextKey), findsOneWidget);
  expect(_hasTransitionAbove(tester, find.byKey(_nextKey)), isFalse);
  expect(tester.getTopLeft(find.byKey(_nextKey)), Offset.zero);
}

void main() {
  testWidgets('neither flag leaves motion on', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(_app(probe));

    expect(probe.reduceMotion, isFalse);
    expect(probe.theme!.splashFactory, isNot(NoSplash.splashFactory));

    await _pushNext(tester);
    expect(
      _hasTransitionAbove(tester, find.byKey(_nextKey)),
      isTrue,
      reason: 'control: the default route transition is present',
    );
  });

  testWidgets('OS flag turns motion off and pages appear on the first frame', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final probe = _Probe();
    await tester.pumpWidget(_app(probe));

    _expectReduced(probe);
    await _expectPageAppearsInstantly(tester);
  });

  testWidgets(
    'app flag alone turns motion off and pages appear on the first frame',
    (tester) async {
      final probe = _Probe();
      await tester.pumpWidget(
        _app(
          probe,
          overrides: [appReduceMotionProvider.overrideWithValue(true)],
        ),
      );

      _expectReduced(probe);
      await _expectPageAppearsInstantly(tester);
    },
  );

  testWidgets(
    'reader route transition returns the page unchanged when reduced',
    (tester) async {
      final probe = _Probe();
      await tester.pumpWidget(
        _app(
          probe,
          overrides: [appReduceMotionProvider.overrideWithValue(true)],
        ),
      );

      const route = ReaderRoute(mangaId: 1, chapterId: 1, transVertical: false);
      const page = SizedBox(key: ValueKey('page'));
      const animation = AlwaysStoppedAnimation<double>(0);

      final result = route.transitionsBuilder(
        probe.context!,
        animation,
        animation,
        page,
      );
      expect(identical(result, page), isTrue);
    },
  );

  testWidgets('reader route transition still slides when motion is on', (
    tester,
  ) async {
    final probe = _Probe();
    await tester.pumpWidget(_app(probe));

    const route = ReaderRoute(mangaId: 1, chapterId: 1, transVertical: false);
    const page = SizedBox(key: ValueKey('page'));
    const animation = AlwaysStoppedAnimation<double>(0);

    final result = route.transitionsBuilder(
      probe.context!,
      animation,
      animation,
      page,
    );
    expect(identical(result, page), isFalse);
  });
}
