import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

final _navigatorKey = GlobalKey<NavigatorState>();

Widget _app(Widget Function(BuildContext context) body) => ProviderScope(
  overrides: [appReduceMotionProvider.overrideWith(_ReduceMotionOn.new)],
  child: MaterialApp(
    navigatorKey: _navigatorKey,
    builder: (context, child) => ReduceMotionScope(child: child!),
    home: Builder(
      builder: (context) => Scaffold(body: Builder(builder: body)),
    ),
  ),
);

void main() {
  testWidgets('back-to-back snackbars under reduced motion show in turn', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        (context) => TextButton(
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('first'),
                duration: Duration(milliseconds: 300),
              ),
              snackBarAnimationStyle: context.snackBarMotionStyle,
            );
            messenger.showSnackBar(
              const SnackBar(
                content: Text('second'),
                duration: Duration(milliseconds: 300),
              ),
              snackBarAnimationStyle: context.snackBarMotionStyle,
            );
          },
          child: const Text('show'),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    for (var step = 0; step < 12; step++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('second'), findsOneWidget);

    for (var step = 0; step < 30; step++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsNothing);
  });

  testWidgets(
    'a reduced-motion dialog opens and closes with no leftover route',
    (tester) async {
      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              animationStyle: context.motionStyle,
              builder: (dialogContext) => AlertDialog(
                content: const Text('dialog body'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('close dialog'),
                  ),
                ],
              ),
            ),
            child: const Text('dialog'),
          ),
        ),
      );

      await tester.tap(find.text('dialog'));
      await tester.pump();
      expect(find.text('dialog body'), findsOneWidget);

      await tester.tap(find.text('close dialog'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('dialog body'), findsNothing);
      expect(_navigatorKey.currentState!.canPop(), isFalse);
    },
  );

  testWidgets(
    'a reduced-motion bottom sheet opens and closes with no leftover route',
    (tester) async {
      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              sheetAnimationStyle: context.motionStyle,
              builder: (sheetContext) => TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('close sheet'),
              ),
            ),
            child: const Text('sheet'),
          ),
        ),
      );

      await tester.tap(find.text('sheet'));
      await tester.pump();
      expect(find.text('close sheet'), findsOneWidget);

      await tester.tap(find.text('close sheet'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('close sheet'), findsNothing);
      expect(_navigatorKey.currentState!.canPop(), isFalse);
    },
  );
}
