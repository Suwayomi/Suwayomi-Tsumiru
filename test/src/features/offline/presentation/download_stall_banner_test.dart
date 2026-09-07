import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_stall.dart';
import 'package:tsumiru/src/features/offline/presentation/download_stall_banner.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('shows the current reason and retry without overflowing', (
    tester,
  ) async {
    if (const bool.fromEnvironment('CAPTURE_STALL')) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  const String.fromEnvironment('FONT_PATH'),
                ).readAsBytes(),
              ),
            ),
          );
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  const String.fromEnvironment('ICON_FONT_PATH'),
                ).readAsBytes(),
              ),
            ),
          );
        await icons.load();
      });
    }
    tester.view.physicalSize = const Size(412, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveDownloadStallProvider.overrideWith((ref) => 'background'),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DownloadStallBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Android paused background downloads. Open Tsumiru to try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_STALL')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('/tmp/tsumiru-download-stall.png'),
      );
    }
  });
}
