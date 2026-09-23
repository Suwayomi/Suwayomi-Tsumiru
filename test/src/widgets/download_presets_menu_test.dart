// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_download_presets.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/confirm_bulk_download_dialog.dart';
import 'package:tsumiru/src/widgets/download_presets_menu.dart';

Future<void> pumpMenu(
  WidgetTester tester, {
  ValueChanged<DownloadPreset>? onSelected,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DownloadPresetsMenu(enabled: enabled, onSelected: onSelected),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('localized choices return the matching preset', (tester) async {
    final selected = <DownloadPreset>[];
    await pumpMenu(tester, onSelected: selected.add);
    final context = tester.element(find.byType(DownloadPresetsMenu));
    final l10n = AppLocalizations.of(context)!;
    final labels = [
      l10n.downloadNextChapter,
      l10n.downloadNextChaptersN(5),
      l10n.downloadNextChaptersN(10),
      l10n.downloadNextChaptersN(25),
      l10n.downloadUnreadChapters,
      l10n.downloadAllChapters,
    ];
    for (var index = 0; index < labels.length; index++) {
      await tester.tap(find.byIcon(Icons.cloud_download_outlined));
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(labels[index]));
      await tester.pumpAndSettle();
      expect(selected.last, DownloadPreset.values[index]);
    }
    expect(selected, DownloadPreset.values);
  });

  testWidgets('dismissal does not select a preset', (tester) async {
    final selected = <DownloadPreset>[];
    await pumpMenu(tester, onSelected: selected.add);
    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(find.byType(PopupMenuItem<DownloadPreset>), findsNothing);
  });

  testWidgets('disabled or absent callback prevents opening', (tester) async {
    final selected = <DownloadPreset>[];
    await pumpMenu(tester, enabled: false, onSelected: selected.add);
    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<DownloadPreset>), findsNothing);
    expect(selected, isEmpty);
    await pumpMenu(tester);
    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<DownloadPreset>), findsNothing);
  });

  testWidgets(
    'confirmation shows preset description and cancellation is false',
    (tester) async {
      await pumpMenu(tester, onSelected: (_) {});
      final context = tester.element(find.byType(DownloadPresetsMenu));
      const description = 'Download next 5 chapters for each selected series.';
      final result = confirmBulkDownload(
        context,
        summary: '3 series',
        toDevice: false,
        downloadDescription: description,
      );
      await tester.pumpAndSettle();
      expect(find.text(description), findsOneWidget);
      expect(find.textContaining('Every chapter'), findsNothing);
      await tester.tap(find.text(AppLocalizations.of(context)!.cancel));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    },
  );
}
