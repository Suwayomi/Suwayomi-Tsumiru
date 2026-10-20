import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/hotkeys/data/hotkey_binding.dart';

void main() {
  test('global hotkey registry is consistent', () {
    for (final h in globalHotkeys) {
      expect(h.displayKeys, isNotEmpty);
    }
    final byKeys = {for (final h in globalHotkeys) h.displayKeys.join('+'): h};
    // Library and downloads are desktop-only; back is not.
    expect(byKeys['Ctrl+L']!.desktopOnly, isTrue);
    expect(byKeys['Ctrl+J']!.desktopOnly, isTrue);
    expect(byKeys['Esc']!.desktopOnly, isFalse);
    // No forward row exists.
    expect(
      globalHotkeys.any((h) => h.displayKeys.contains('Forward')),
      isFalse,
    );
    // Desktop activators include the desktop-only binds.
    expect(
      activeGlobalHotkeys().map((h) => h.displayKeys.join('+')),
      containsAll(<String>['Esc', 'Ctrl+L', 'Ctrl+J']),
    );
    // Mouse back is handled by a Listener, so it has no keyboard activator;
    // Esc and Alt+Left are real keybinds.
    expect(byKeys['Mouse+Back']!.hasKeyboardActivator, isFalse);
    expect(byKeys['Esc']!.hasKeyboardActivator, isTrue);
    expect(byKeys['Alt+←']!.hasKeyboardActivator, isTrue);
  });
}
