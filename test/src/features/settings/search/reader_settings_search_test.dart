// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Slice 2: searching "zoom" returns exactly the 7 zoom rows (4 Paged, 3
// Long strip) with their section breadcrumbs, and opening the Long strip
// "Disable zoom out" result on a 600 px tall surface scrolls that far-down
// row into view and highlights it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/reader_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

/// Whether [element]'s row is mid-pulse: its highlight tint is up. The
/// bar shows earlier (during the pre-pulse pause), so waiting for the tint
/// proves the row was scrolled into view and the pulse actually started.
bool _elementHighlighted(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    final decoration = widget is DecoratedBox ? widget.decoration : null;
    if (decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0) {
      found = true;
    }
    return true;
  });
  return found;
}

/// Id of the nearest [SettingsHighlightTarget] above [element], i.e. which
/// setting row the element belongs to. Duplicate titles (Paged/Long strip
/// twins) share their text but never their target id.
String? _targetIdOf(Element element) {
  String? id;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is SettingsHighlightTarget) id ??= widget.id;
    return true;
  });
  return id;
}

void main() {
  final l = AppLocalizationsEn();

  group('reader settings search', () {
    test('zoom finds the 7 zoom rows with paged/long-strip breadcrumbs', () {
      expect(readerSettingsSearchEntries, hasLength(52));
      final hits = matchSettingsEntries(
        entries: allSettingsSearchEntries,
        l: l,
        query: 'zoom',
        isVisible: (_) => true,
      );
      expect(
        hits.map((e) => e.id).toList(),
        [
          'disableZoomIn',
          'pagedDoubleTapToZoom',
          'pagedPinchToZoom',
          'pagedDisableZoomOut',
          'longStripDoubleTapToZoom',
          'longStripPinchToZoom',
          'longStripDisableZoomOut',
        ],
      );
      final paged = '${l.reader} › ${l.readerGroupPagerViewer}';
      final strip = '${l.reader} › ${l.readerGroupWebtoonViewer}';
      for (final hit in hits.take(4)) {
        expect(hit.breadcrumb(l), paged, reason: hit.id);
      }
      for (final hit in hits.skip(4)) {
        expect(hit.breadcrumb(l), strip, reason: hit.id);
      }
    });

    testWidgets('Long strip Disable zoom out scrolls into view and pulses', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      debugAndroidOverride = true;
      addTearDown(() => debugAndroidOverride = null);
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      container.read(forceHorizontalSeekbarProvider.notifier).update(false);
      container.read(readerFullscreenProvider.notifier).update(true);
      container.read(flashOnPageChangeProvider.notifier).update(true);
      container.read(dualPageSplitPagedProvider.notifier).update(true);
      container.read(rotateWidePagesProvider.notifier).update(true);
      container.read(volumeTapProvider.notifier).update(true);
      final router = GoRouter(
        initialLocation: '/reader?highlight=longStripDisableZoomOut',
        routes: [
          GoRoute(
            path: '/reader',
            builder: (_, _) => const ReaderSettingsScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );

      // The strip row starts far down the lazily built list; the scope's
      // seeker steps toward it about one viewport per frame until it
      // mounts, centres, and lights up. Rows outside the cache extent
      // unmount, so the Paged twin with the same title may never be in the
      // tree at the same time — identify the lit row by its target id.
      Element? lit;
      for (var i = 0; i < 120 && lit == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final matches = find
            .text(l.disableZoomOut)
            .evaluate()
            .where(_elementHighlighted)
            .toList();
        if (matches.length == 1) lit = matches.single;
      }
      if (lit == null) fail('long-strip row never lit up');
      // This is the far-down Long strip row the search result opens, not
      // the earlier Paged row with the same title.
      expect(_targetIdOf(lit), 'longStripDisableZoomOut');
      final dy = tester.getCenter(find.byWidget(lit.widget)).dy;
      expect(dy, inInclusiveRange(0, 600));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
