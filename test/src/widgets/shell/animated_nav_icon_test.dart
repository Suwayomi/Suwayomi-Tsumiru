import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/animated_nav_vectors.dart';
import 'package:tsumiru/src/widgets/shell/animated_nav_icon.dart';

// Paints every nav vector through its full forward and reverse run. Path
// strings parse lazily and morph-compatibility is only asserted during lerp,
// so a bad transcription would crash at first paint — this catches it.
void main() {
  const vectors = {
    'library': AnimatedNavVectors.library,
    'updates': AnimatedNavVectors.updates,
    'history': AnimatedNavVectors.history,
    'browse': AnimatedNavVectors.browse,
    'more': AnimatedNavVectors.more,
    'downloads': AnimatedNavVectors.downloads,
  };

  Widget host(String name, {required bool selected}) {
    return MaterialApp(
      home: Scaffold(
        body: AnimatedNavIcon(vector: vectors[name]!, selected: selected),
      ),
    );
  }

  for (final name in vectors.keys) {
    testWidgets('$name paints through select and deselect', (tester) async {
      await tester.pumpWidget(host(name, selected: false));

      await tester.pumpWidget(host(name, selected: true));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pumpWidget(host(name, selected: false));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    testWidgets('$name mounts already-selected at the settled frame',
        (tester) async {
      await tester.pumpWidget(host(name, selected: true));
      expect(tester.hasRunningAnimations, isFalse);
    });
  }
}
