// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../utils/platform/platform_runtime.dart';

class GoBackIntent extends Intent {
  const GoBackIntent();
}

/// Bind directly in the host: pushed routes do not propagate DismissIntent to it.
class EscapeIntent extends Intent {
  const EscapeIntent();
}

class OpenLibraryIntent extends Intent {
  const OpenLibraryIntent();
}

class OpenDownloadsIntent extends Intent {
  const OpenDownloadsIntent();
}

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}

/// Sentinel for non-keyboard rows, excluded from the Shortcuts map.
class _NoActivator extends ShortcutActivator {
  const _NoActivator();
  @override
  Iterable<LogicalKeyboardKey>? get triggers => const [];
  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) => false;
  @override
  String debugDescribeKeys() => '';
}

const ShortcutActivator noActivator = _NoActivator();

class GlobalHotkey {
  const GlobalHotkey({
    required this.activator,
    required this.intent,
    required this.label,
    required this.displayKeys,
    this.desktopOnly = false,
  });

  final ShortcutActivator activator;
  final Intent intent;
  final String Function(AppLocalizations) label;
  final List<String> displayKeys;
  final bool desktopOnly;

  bool get hasKeyboardActivator => activator is! _NoActivator;
}

String _backLabel(AppLocalizations l) => l.hotkeyGoBack;
String _searchLabel(AppLocalizations l) => l.hotkeyOpenSearch;
String _libraryLabel(AppLocalizations l) => l.hotkeyOpenLibrary;
String _downloadsLabel(AppLocalizations l) => l.hotkeyOpenDownloads;

// Shared labels group bindings into one row; registry order determines page order.
const List<GlobalHotkey> globalHotkeys = [
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.escape),
    intent: EscapeIntent(),
    label: _backLabel,
    displayKeys: ['Esc'],
  ),
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
    intent: GoBackIntent(),
    label: _backLabel,
    displayKeys: ['Alt', '←'],
  ),
  GlobalHotkey(
    activator: noActivator, // mouse button 4, handled by Listener
    intent: GoBackIntent(),
    label: _backLabel,
    displayKeys: ['Mouse', 'Back'],
  ),
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.keyF, control: true),
    intent: OpenSearchIntent(),
    label: _searchLabel,
    displayKeys: ['Ctrl', 'F'],
  ),
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.keyP, control: true),
    intent: OpenSearchIntent(),
    label: _searchLabel,
    displayKeys: ['Ctrl', 'P'],
  ),
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.keyL, control: true),
    intent: OpenLibraryIntent(),
    label: _libraryLabel,
    displayKeys: ['Ctrl', 'L'],
    desktopOnly: true,
  ),
  GlobalHotkey(
    activator: SingleActivator(LogicalKeyboardKey.keyJ, control: true),
    intent: OpenDownloadsIntent(),
    label: _downloadsLabel,
    displayKeys: ['Ctrl', 'J'],
    desktopOnly: true,
  ),
];

List<GlobalHotkey> activeGlobalHotkeys() =>
    globalHotkeys.where((h) => !h.desktopOnly || isDesktopPlatform).toList();

class HotkeyDisplay {
  const HotkeyDisplay({required this.label, required this.displayKeys});
  final String Function(AppLocalizations) label;
  final List<String> displayKeys;
}

String _rPrevPage(AppLocalizations l) => l.hotkeyReaderPrevPage;
String _rNextPage(AppLocalizations l) => l.hotkeyReaderNextPage;
String _rFirstPage(AppLocalizations l) => l.hotkeyReaderFirstPage;
String _rLastPage(AppLocalizations l) => l.hotkeyReaderLastPage;
String _rPrevChapter(AppLocalizations l) => l.hotkeyReaderPrevChapter;
String _rNextChapter(AppLocalizations l) => l.hotkeyReaderNextChapter;
String _rToggleMenu(AppLocalizations l) => l.hotkeyReaderToggleMenu;

const List<HotkeyDisplay> readerHotkeyDisplays = [
  HotkeyDisplay(label: _rPrevPage, displayKeys: ['←', 'A']),
  HotkeyDisplay(label: _rNextPage, displayKeys: ['→', 'D']),
  HotkeyDisplay(label: _rFirstPage, displayKeys: ['Home']),
  HotkeyDisplay(label: _rLastPage, displayKeys: ['End']),
  HotkeyDisplay(label: _rPrevChapter, displayKeys: [',']),
  HotkeyDisplay(label: _rNextChapter, displayKeys: ['.']),
  HotkeyDisplay(label: _rToggleMenu, displayKeys: ['Esc']),
];
