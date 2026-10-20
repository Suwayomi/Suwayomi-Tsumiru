import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/hotkeys/presentation/global_shortcut_host.dart';

// Faithful reproduction: the host wraps a router shell and NOTHING is given
// focus (exactly like the real app at the library screen). A `Shortcuts`
// widget only receives key events when a focused widget lives below it, so
// these must pass without any test-side autofocus. The previous test cheated
// with `Focus(autofocus: true)`, which hid the real bug — every app-wide
// shortcut was dead because nothing ever holds focus.
//
// The host navigates via the app's typed LibraryRoute (`/library/0`) and
// DownloadsRoute (`/downloads`); this test router provides plain routes at
// those exact locations so Ctrl+L / Ctrl+J are exercised for real.

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => GlobalShortcutHost(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/b'),
                child: const Text('to B'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/b',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('PAGE B'))),
        ),
        GoRoute(
          path: '/library/:categoryId',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('LIBRARY'))),
        ),
        GoRoute(
          path: '/downloads',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('DOWNLOADS'))),
        ),
      ],
    ),
  ],
);

Future<void> _defocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

Future<void> _pumpRouter(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: _router())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back keys pop the route with nothing pre-focused', (
    tester,
  ) async {
    Future<void> openB() async {
      await tester.tap(find.text('to B'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE B'), findsOneWidget);
      await _defocus(tester);
    }

    await _pumpRouter(tester);

    // Esc.
    await openB();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PAGE B'), findsNothing, reason: 'Esc should go back');
    expect(find.text('to B'), findsOneWidget);

    // Alt+Left.
    await openB();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      find.text('PAGE B'),
      findsNothing,
      reason: 'Alt+Left should go back',
    );

    // Mouse back-button.
    await openB();
    final center = tester.getCenter(find.text('PAGE B'));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(center, buttons: kBackMouseButton),
    );
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(pointer.up());
    expect(
      find.text('PAGE B'),
      findsNothing,
      reason: 'mouse back-button should go back',
    );
  });

  testWidgets('Ctrl+L opens the library with nothing pre-focused', (
    tester,
  ) async {
    await _pumpRouter(tester);
    await _defocus(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('LIBRARY'), findsOneWidget, reason: 'Ctrl+L → library');
  });

}
