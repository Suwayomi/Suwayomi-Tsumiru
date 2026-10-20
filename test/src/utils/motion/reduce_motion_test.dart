import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

const _nextKey = ValueKey('next');

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

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

Future<void> _popNext(WidgetTester tester, _Probe probe) async {
  await tester.pumpAndSettle();
  Navigator.of(probe.context!).pop();
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
  testWidgets('OS and app flags turn motion off, at runtime and on routes', (
    tester,
  ) async {
    // Neither flag leaves motion on.
    final control = _Probe();
    await tester.pumpWidget(_app(control));
    expect(control.reduceMotion, isFalse);
    expect(control.theme!.splashFactory, isNot(NoSplash.splashFactory));
    await _pushNext(tester);
    expect(
      _hasTransitionAbove(tester, find.byKey(_nextKey)),
      isTrue,
      reason: 'control: the default route transition is present',
    );

    // OS flag.
    await tester.pumpWidget(const SizedBox.shrink());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final osProbe = _Probe();
    await tester.pumpWidget(_app(osProbe));
    _expectReduced(osProbe);
    await _expectPageAppearsInstantly(tester);

    // App flag alone.
    await tester.pumpWidget(const SizedBox.shrink());
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    final appProbe = _Probe();
    await tester.pumpWidget(
      _app(
        appProbe,
        overrides: [appReduceMotionProvider.overrideWith(_ReduceMotionOn.new)],
      ),
    );
    _expectReduced(appProbe);
    await _expectPageAppearsInstantly(tester);

    // set(true) at runtime turns reduced motion on below the scope.
    await tester.pumpWidget(const SizedBox.shrink());
    final runtimeProbe = _Probe();
    await tester.pumpWidget(_app(runtimeProbe));
    expect(runtimeProbe.reduceMotion, isFalse);
    ProviderScope.containerOf(
      runtimeProbe.context!,
    ).read(appReduceMotionProvider.notifier).set(true);
    await tester.pump();
    _expectReduced(runtimeProbe);

    // A closing page is hidden at once when reduced.
    await tester.pumpWidget(const SizedBox.shrink());
    final reducedProbe = _Probe();
    await tester.pumpWidget(
      _app(
        reducedProbe,
        overrides: [appReduceMotionProvider.overrideWith(_ReduceMotionOn.new)],
      ),
    );
    await _pushNext(tester);
    await _popNext(tester, reducedProbe);
    expect(find.byKey(_nextKey), findsNothing);
    expect(find.byKey(_nextKey, skipOffstage: false), findsOneWidget);
    expect(find.text('open'), findsOneWidget);

    // The reader route wraps in the closing-page hider when reduced.
    const route = ReaderRoute(mangaId: 1, chapterId: 1, transVertical: false);
    const page = SizedBox(key: ValueKey('page'));
    const animation = AlwaysStoppedAnimation<double>(0);
    final reduced = route.transitionsBuilder(
      reducedProbe.context!,
      animation,
      animation,
      page,
    );
    expect(
      reduced,
      isA<ReducedRouteTransition>().having((w) => w.child, 'child', same(page)),
    );

    // Without reduced motion the closing page is still painted on the first
    // pop frame.
    await tester.pumpWidget(const SizedBox.shrink());
    final motionProbe = _Probe();
    await tester.pumpWidget(_app(motionProbe));
    await _pushNext(tester);
    await _popNext(tester, motionProbe);
    expect(find.byKey(_nextKey), findsOneWidget);

    // And the reader still slides when motion is on.
    final sliding = route.transitionsBuilder(
      motionProbe.context!,
      animation,
      animation,
      page,
    );
    expect(identical(sliding, page), isFalse);
  });
}
