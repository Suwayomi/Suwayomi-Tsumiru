import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/hotkeys/data/hotkey_binding.dart';

void main() {
  test('reader zoom shortcut displays the platform modifier', () {
    final macOSDisplays = readerHotkeyDisplaysForPlatform(
      TargetPlatform.macOS,
      isKeyboardRuntime: true,
    );
    final windowsDisplays = readerHotkeyDisplaysForPlatform(
      TargetPlatform.windows,
      isKeyboardRuntime: true,
    );

    expect(macOSDisplays.last.displayKeys, ['Cmd', 'Scroll']);
    expect(macOSDisplays.last.additionalChords, [
      ['Cmd', 'Pinch'],
    ]);
    expect(windowsDisplays.last.displayKeys, ['Ctrl', 'Scroll']);
    expect(windowsDisplays.last.additionalChords, [
      ['Ctrl', 'Pinch'],
    ]);
  });

  test('reader zoom shortcut is omitted outside keyboard runtimes', () {
    final displays = readerHotkeyDisplaysForPlatform(
      TargetPlatform.iOS,
      isKeyboardRuntime: false,
    );

    expect(displays, hasLength(readerHotkeyDisplays.length));
  });
}
