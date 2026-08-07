import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/hotkeys/data/hotkey_binding.dart';

void main() {
  test('every global hotkey has display keys', () {
    for (final h in globalHotkeys) {
      expect(h.displayKeys, isNotEmpty);
    }
  });

  test('library and downloads are desktop-only; back is not', () {
    final byKeys = {for (final h in globalHotkeys) h.displayKeys.join('+'): h};
    expect(byKeys['Ctrl+L']!.desktopOnly, isTrue);
    expect(byKeys['Ctrl+J']!.desktopOnly, isTrue);
    expect(byKeys['Esc']!.desktopOnly, isFalse);
  });

  test('no forward row exists', () {
    expect(globalHotkeys.any((h) => h.displayKeys.contains('Forward')), isFalse);
  });

  test('activeGlobalHotkeys on desktop includes desktop-only binds', () {
    final active = activeGlobalHotkeys().map((h) => h.displayKeys.join('+'));
    expect(active, containsAll(<String>['Esc', 'Ctrl+L', 'Ctrl+J']));
  });

  test('mouse-back is display-only; Esc and Alt+Left are real keybinds', () {
    final byKeys = {for (final h in globalHotkeys) h.displayKeys.join('+'): h};
    // Mouse back is handled by a Listener, so it has no keyboard activator.
    expect(byKeys['Mouse+Back']!.hasKeyboardActivator, isFalse);
    // Esc is bound directly in the host Shortcuts (not via DismissIntent).
    expect(byKeys['Esc']!.hasKeyboardActivator, isTrue);
    expect(byKeys['Alt+←']!.hasKeyboardActivator, isTrue);
  });
}
